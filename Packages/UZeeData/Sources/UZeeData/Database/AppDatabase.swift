import Foundation
import GRDB

/// Owns the SQLite database and its migrations.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// Append-only list of migrations. Never edit a shipped migration; add a new one.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        // Never wipe user data on schema change, not even in Debug.
        migrator.eraseDatabaseOnSchemaChange = false
        migrator.registerMigration("v1_baseline") { db in
            try db.create(table: "settings") { t in
                t.primaryKey("id", .text)
                t.column("key", .text).notNull().unique()
                t.column("value", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }
        return migrator
    }

    /// Names of migrations applied to this database, oldest first.
    public func appliedMigrations() throws -> [String] {
        try writer.read { db in try Self.migrator.appliedMigrations(db) }
    }

    /// True when every registered migration has been applied.
    public func isUpToDate() throws -> Bool {
        try writer.read { db in try Self.migrator.hasCompletedMigrations(db) }
    }
}

extension AppDatabase {
    /// The on-device database in Application Support/UZee, WAL mode,
    /// protected until the user first unlocks the device after a restart.
    public static func onDisk(fileManager: FileManager = .default) throws -> AppDatabase {
        let folder = try StorageLocation.databaseFolder(fileManager: fileManager)
        var config = Configuration()
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: folder.appendingPathComponent("uzee.sqlite").path, configuration: config)
        return try AppDatabase(pool)
    }

    /// Empty in-memory database for tests and previews.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }
}
