import Foundation
import UZeeCore

/// Receipt files on disk (ATT-003): one folder inside UZee's protected storage, random file names,
/// readable only while the phone is unlocked. File names are never logged.
public struct AttachmentStore: Sendable {
    public enum Problem: Error, Equatable, Sendable {
        case tooLarge
        case empty
    }

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// Attachments folder next to the database.
    public static func onDisk(fileManager: FileManager = .default) throws -> AttachmentStore {
        let folder = try StorageLocation.databaseFolder(fileManager: fileManager).appendingPathComponent("Attachments", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return AttachmentStore(folder: folder)
    }

    /// A throwaway folder for UI tests and previews.
    public static func temporary() throws -> AttachmentStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("UZeeAttachments-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return AttachmentStore(folder: folder)
    }

    /// Writes the bytes under a new random name and returns that name.
    public func write(_ data: Data, kind: ReceiptFile.Kind) throws -> String {
        guard !data.isEmpty else { throw Problem.empty }
        guard Int64(data.count) <= ReceiptFile.maxBytes else { throw Problem.tooLarge }
        let name = UUID().uuidString + (kind == .pdf ? ".pdf" : ".jpg")
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtection)
        #endif
        try data.write(to: url(for: name), options: options)
        return name
    }

    /// A stored name must be one plain file inside `folder`: no path separators, no `.`/`..`,
    /// no hidden names. Names come from the database, which a restored backup can supply,
    /// so they are never trusted as paths.
    public static func isSafeFileName(_ fileName: String) -> Bool {
        guard !fileName.isEmpty, fileName.count <= 255,
              !fileName.hasPrefix("."),
              !fileName.contains("/"), !fileName.contains("\\"), !fileName.contains("\0")
        else { return false }
        return true
    }

    /// The file's location inside `folder`. An unsafe name maps to a path that is never written,
    /// so reads find nothing and deletes do nothing.
    public func url(for fileName: String) -> URL {
        let name = Self.isSafeFileName(fileName) ? fileName : ".invalid-attachment-name"
        let url = folder.appendingPathComponent(name, isDirectory: false)
        // Belt and braces: the result must sit directly in `folder`.
        guard url.standardizedFileURL.deletingLastPathComponent().path == folder.standardizedFileURL.path else {
            return folder.appendingPathComponent(".invalid-attachment-name", isDirectory: false)
        }
        return url
    }

    /// Deletes files; missing ones and unsafe names are ignored.
    public func remove(_ fileNames: some Sequence<String>) {
        for name in fileNames where Self.isSafeFileName(name) {
            try? FileManager.default.removeItem(at: url(for: name))
        }
    }

    /// Deletes files the database no longer knows (left by a crash between the two writes).
    public func removeOrphans(keeping known: Set<String>) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        remove(names.filter { !known.contains($0) })
    }
}
