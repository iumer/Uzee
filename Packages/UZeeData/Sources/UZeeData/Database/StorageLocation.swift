import Foundation

/// Where UZee keeps its files. Only data lives here; nothing is synced yet.
public enum StorageLocation {
    public static func databaseFolder(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = support.appendingPathComponent("UZee", isDirectory: true)
        var attributes: [FileAttributeKey: Any] = [:]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        if !fileManager.fileExists(atPath: folder.path) {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: attributes)
        } else if !attributes.isEmpty {
            try fileManager.setAttributes(attributes, ofItemAtPath: folder.path)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true // backups are UZee's own encrypted files, not iCloud device backup
        var mutable = folder
        try? mutable.setResourceValues(values)
        return folder
    }
}
