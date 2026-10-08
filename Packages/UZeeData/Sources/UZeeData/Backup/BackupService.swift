import Foundation
import GRDB
import UZeeCore

/// Password-encrypted backup and restore (DATA-02, §13). The file is a short readable header
/// ("UZEE-BACKUP 1", the format, date, app version and key-derivation settings) followed by one sealed box
/// holding a copy of the database and every receipt. The password is never stored; the sealing itself is
/// supplied by UZeeSystem (AES-GCM with a PBKDF2 key), so this layer stays testable on Linux.
public struct BackupService: Sendable {
    /// Seals or opens bytes with a password; `open` throws when the password is wrong or the bytes changed.
    public struct Cipher: Sendable {
        public var seal: @Sendable (_ plain: Data, _ password: String, _ salt: Data, _ iterations: Int) throws -> Data
        public var open: @Sendable (_ sealed: Data, _ password: String, _ salt: Data, _ iterations: Int) throws -> Data
        public var iterations: Int

        public init(iterations: Int, seal: @escaping @Sendable (Data, String, Data, Int) throws -> Data,
                    open: @escaping @Sendable (Data, String, Data, Int) throws -> Data) {
            self.iterations = iterations
            self.seal = seal
            self.open = open
        }
    }

    struct Header: Codable {
        var format: Int
        var createdAt: Date
        var appVersion: String
        var kdf: String
        var iterations: Int
        var salt: String
    }

    static let magic = Data("UZEE-BACKUP 1\n".utf8)
    static let format = 1
    static let databaseName = "uzee.sqlite"

    let database: AppDatabase
    let attachments: AttachmentStore
    let cipher: Cipher

    public init(database: AppDatabase, attachments: AttachmentStore, cipher: Cipher) {
        self.database = database
        self.attachments = attachments
        self.cipher = cipher
    }

    // MARK: Make

    /// The whole backup file.
    public func makeBackup(password: String, appVersion: String, now: Date = Date()) throws -> Data {
        guard password.count >= BackupProblem.minimumPasswordLength else { throw BackupProblem.weakPassword }
        let work = try Self.workFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        let copy = work.appendingPathComponent(Self.databaseName)
        // A consistent copy of the live database, even while it is in use.
        try database.writer.backup(to: try DatabaseQueue(path: copy.path))
        var files: [(String, Data)] = [(Self.databaseName, try Data(contentsOf: copy))]
        for name in try receiptNames() {
            if let data = try? Data(contentsOf: attachments.url(for: name)) { files.append(("receipts/" + name, data)) }
        }
        var salt = Data(count: 16)
        var generator = SystemRandomNumberGenerator()
        for index in salt.indices { salt[index] = UInt8.random(in: .min ... .max, using: &generator) }
        let header = Header(format: Self.format, createdAt: now, appVersion: appVersion, kdf: "PBKDF2-SHA256",
                            iterations: cipher.iterations, salt: salt.base64EncodedString())
        let sealed = try cipher.seal(Self.pack(files), password, salt, cipher.iterations)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return Self.magic + (try encoder.encode(header)) + Data("\n".utf8) + sealed
    }

    // MARK: Read

    struct Opened {
        var header: Header
        var files: [String: Data]
    }

    func open(_ file: Data, password: String) throws -> Opened {
        guard file.starts(with: Self.magic) else { throw BackupProblem.notABackup }
        let rest = file.dropFirst(Self.magic.count)
        guard let newline = rest.firstIndex(of: UInt8(ascii: "\n")) else { throw BackupProblem.notABackup }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let header = try? decoder.decode(Header.self, from: Data(rest[rest.startIndex..<newline])),
              let salt = Data(base64Encoded: header.salt) else { throw BackupProblem.notABackup }
        guard header.format <= Self.format else { throw BackupProblem.tooNew }
        let plain: Data
        do { plain = try cipher.open(Data(rest[rest.index(after: newline)...]), password, salt, header.iterations) } catch {
            throw BackupProblem.wrongPasswordOrDamaged
        }
        guard let files = Self.unpack(plain), files[Self.databaseName] != nil else { throw BackupProblem.wrongPasswordOrDamaged }
        return Opened(header: header, files: files)
    }

    /// Opens the backup's database in a work folder, brought up to this version's schema and checked.
    private func restoredDatabase(_ opened: Opened, in work: URL) throws -> (DatabaseQueue, BackupSummary) {
        let path = work.appendingPathComponent(Self.databaseName)
        try opened.files[Self.databaseName]!.write(to: path)
        let queue: DatabaseQueue
        do {
            var config = Configuration()
            config.foreignKeysEnabled = true
            queue = try DatabaseQueue(path: path.path, configuration: config)
            _ = try AppDatabase(queue)
            let check = try queue.read { try String.fetchOne($0, sql: "PRAGMA integrity_check") }
            guard check == "ok" else { throw BackupProblem.wrongPasswordOrDamaged }
        } catch let problem as BackupProblem {
            throw problem
        } catch {
            throw BackupProblem.wrongPasswordOrDamaged
        }
        let summary = try queue.read { db in
            BackupSummary(createdAt: opened.header.createdAt, appVersion: opened.header.appVersion,
                          transactions: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM txn WHERE deleted_at IS NULL") ?? 0,
                          accounts: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM account WHERE deleted_at IS NULL") ?? 0,
                          receipts: opened.files.keys.filter { $0.hasPrefix("receipts/") }.count)
        }
        return (queue, summary)
    }

    /// Checks the password and reads what the backup holds, without changing anything.
    public func inspect(_ file: Data, password: String) throws -> BackupSummary {
        let opened = try open(file, password: password)
        let work = try Self.workFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        return try restoredDatabase(opened, in: work).1
    }

    // MARK: Restore

    /// Replaces everything with the backup. A safety copy of the current data is saved in `safetyFolder` first;
    /// if anything fails before the swap, nothing is changed.
    @discardableResult
    public func restore(_ file: Data, password: String, safetyFolder: URL, now: Date = Date()) throws -> BackupSummary {
        let opened = try open(file, password: password)
        let work = try Self.workFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        let (restored, summary) = try restoredDatabase(opened, in: work)

        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let safety = safetyFolder.appendingPathComponent("Before restore \(stamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: safety, withIntermediateDirectories: true)
        try database.writer.backup(to: try DatabaseQueue(path: safety.appendingPathComponent(Self.databaseName).path))
        let receiptsCopy = safety.appendingPathComponent("Receipts", isDirectory: true)
        try? FileManager.default.copyItem(at: attachments.folder, to: receiptsCopy)

        try restored.backup(to: database.writer)
        let current = (try? FileManager.default.contentsOfDirectory(atPath: attachments.folder.path)) ?? []
        attachments.remove(current)
        try FileManager.default.createDirectory(at: attachments.folder, withIntermediateDirectories: true)
        for (name, data) in opened.files where name.hasPrefix("receipts/") {
            let file = String(name.dropFirst("receipts/".count))
            guard !file.isEmpty, !file.contains("/"), !file.hasPrefix(".") else { continue }
            try data.write(to: attachments.url(for: file), options: .atomic)
        }
        return summary
    }

    // MARK: Helpers

    private func receiptNames() throws -> [String] {
        try database.writer.read { db in try String.fetchAll(db, sql: "SELECT file_name FROM attachment WHERE deleted_at IS NULL") }
    }

    static func workFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("UZeeBackup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// name length (UInt32), name, size (UInt64), bytes — repeated. Big-endian.
    static func pack(_ files: [(String, Data)]) -> Data {
        var out = Data()
        for (name, data) in files {
            let nameData = Data(name.utf8)
            out.append(contentsOf: withUnsafeBytes(of: UInt32(nameData.count).bigEndian, Array.init))
            out.append(nameData)
            out.append(contentsOf: withUnsafeBytes(of: UInt64(data.count).bigEndian, Array.init))
            out.append(data)
        }
        return out
    }

    static func unpack(_ data: Data) -> [String: Data]? {
        var files: [String: Data] = [:]
        var index = data.startIndex
        func read(_ count: Int) -> Data? {
            guard count >= 0, data.distance(from: index, to: data.endIndex) >= count else { return nil }
            defer { index = data.index(index, offsetBy: count) }
            return Data(data[index..<data.index(index, offsetBy: count)])
        }
        func number(_ bytes: Int) -> UInt64? {
            read(bytes).map { $0.reduce(UInt64(0)) { $0 << 8 | UInt64($1) } }
        }
        while index < data.endIndex {
            guard let nameLength = number(4), nameLength < 4_096, let nameData = read(Int(nameLength)),
                  let name = String(data: nameData, encoding: .utf8), let size = number(8), size < UInt64(Int.max),
                  let bytes = read(Int(size)) else { return nil }
            files[name] = bytes
        }
        return files
    }
}
