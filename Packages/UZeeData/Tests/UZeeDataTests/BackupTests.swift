import Foundation
import Testing
import GRDB
import UZeeCore
@testable import UZeeData

/// DATA-020…026: backup → wipe → restore gives back every record and receipt; a wrong password or a changed
/// file is refused without touching anything. The test cipher stands in for AES-GCM (UZeeSystem).
@Suite("Backup and restore")
struct BackupTests {
    /// XOR with the password, plus a password check and a checksum, so wrong passwords and edits are caught.
    static let testCipher = BackupService.Cipher(iterations: 1, seal: { plain, password, salt, _ in
        let key = Array((password + salt.base64EncodedString()).utf8)
        let body = Data(plain.enumerated().map { $0.element ^ key[$0.offset % key.count] })
        return Data(key.prefix(8)) + Data(String(plain.reduce(0) { ($0 &* 31 &+ Int($1)) & 0xFFFFFF }).utf8) + Data("|".utf8) + body
    }, open: { sealed, password, salt, _ in
        let key = Array((password + salt.base64EncodedString()).utf8)
        guard sealed.prefix(8) == Data(key.prefix(8)), let bar = sealed.dropFirst(8).firstIndex(of: UInt8(ascii: "|")) else {
            throw BackupProblem.wrongPasswordOrDamaged
        }
        let sum = String(decoding: sealed[sealed.index(sealed.startIndex, offsetBy: 8)..<bar], as: UTF8.self)
        let body = Data(sealed[sealed.index(after: bar)...].enumerated().map { $0.element ^ key[$0.offset % key.count] })
        guard sum == String(body.reduce(0) { ($0 &* 31 &+ Int($1)) & 0xFFFFFF }) else { throw BackupProblem.wrongPasswordOrDamaged }
        return body
    })

    struct World {
        let database: AppDatabase
        let files: AttachmentStore
        let service: BackupService
    }

    func world() throws -> World {
        let database = try AppDatabase.inMemory()
        let files = try AttachmentStore.temporary()
        return World(database: database, files: files, service: BackupService(database: database, attachments: files, cipher: Self.testCipher))
    }

    func counts(_ database: AppDatabase) throws -> [Int] {
        try database.writer.read { db in
            try ["txn", "account", "recurring_item", "person", "attachment"].map {
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \($0)") ?? 0
            }
        }
    }

    @Test("DATA-020 backup, wipe, restore: same records, receipts and a safety copy")
    func roundTrip() throws {
        let world = try world()
        try SampleDataService(database: world.database).load()
        let ledger = LedgerStore(database: world.database)
        let first = try ledger.transactions().first!
        let name = try world.files.write(Data("receipt bytes".utf8), kind: .photo)
        try ledger.addAttachment(ReceiptFile(transactionID: first.id, kind: .photo, fileName: name, byteCount: 13))
        let before = try counts(world.database)

        let file = try world.service.makeBackup(password: "correct horse", appVersion: "1.0 (1)")
        #expect(file.starts(with: Data("UZEE-BACKUP 1\n".utf8)))
        let summary = try world.service.inspect(file, password: "correct horse")
        // The summary counts live transactions; the backup also keeps Recently Deleted ones (compared below).
        let live = try world.database.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM txn WHERE deleted_at IS NULL") ?? 0 }
        #expect(summary.transactions == live)
        #expect(summary.receipts == 1)

        try SampleDataService(database: world.database).removeAll()
        world.files.remove([name])
        #expect(try counts(world.database)[0] == 0)

        let safety = FileManager.default.temporaryDirectory.appendingPathComponent("UZeeSafety-\(UUID())")
        try world.service.restore(file, password: "correct horse", safetyFolder: safety)
        #expect(try counts(world.database) == before)
        #expect(try Data(contentsOf: world.files.url(for: name)) == Data("receipt bytes".utf8))
        let copies = try FileManager.default.contentsOfDirectory(atPath: safety.path)
        #expect(copies.count == 1)
    }

    @Test("DATA-022 wrong password, a changed byte or a random file change nothing")
    func refused() throws {
        let world = try world()
        try SampleDataService(database: world.database).load()
        let before = try counts(world.database)
        let file = try world.service.makeBackup(password: "correct horse", appVersion: "1.0 (1)")
        let safety = FileManager.default.temporaryDirectory.appendingPathComponent("UZeeSafety-\(UUID())")
        #expect(throws: BackupProblem.wrongPasswordOrDamaged) {
            try world.service.restore(file, password: "wrong horse!", safetyFolder: safety)
        }
        var tampered = file
        tampered[tampered.count - 100] ^= 0xFF
        #expect(throws: BackupProblem.wrongPasswordOrDamaged) {
            try world.service.restore(tampered, password: "correct horse", safetyFolder: safety)
        }
        #expect(throws: BackupProblem.notABackup) {
            try world.service.inspect(Data("hello".utf8), password: "correct horse")
        }
        #expect(throws: BackupProblem.weakPassword) { try world.service.makeBackup(password: "short", appVersion: "1") }
        #expect(try counts(world.database) == before)
        #expect(!FileManager.default.fileExists(atPath: safety.path))
    }

    @Test("Archive packing round-trips and rejects truncation")
    func packing() {
        let files = [("a", Data([1, 2, 3])), ("receipts/b.jpg", Data())]
        let packed = BackupService.pack(files)
        #expect(BackupService.unpack(packed) == ["a": Data([1, 2, 3]), "receipts/b.jpg": Data()])
        #expect(BackupService.unpack(packed.dropLast()) == nil)
    }
}
