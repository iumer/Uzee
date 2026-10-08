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
        // M1: per-device settings (DATA_MODEL §3.2). Starts the snake_case convention used by every later table.
        migrator.registerMigration("v2_device_settings") { db in
            try db.create(table: "device_settings") { t in
                t.primaryKey("id", .text)
                t.column("app_lock_enabled", .integer).notNull().defaults(to: 0).check { [0, 1].contains($0) }
                t.column("lock_timeout_seconds", .integer).notNull().defaults(to: 60)
                t.column("calendar_export_mode", .text).notNull().defaults(to: "off")
                t.column("calendar_identifier", .text)
                t.column("sample_mode_active", .integer).notNull().defaults(to: 0).check { [0, 1].contains($0) }
                t.column("updated_at", .integer).notNull()
            }
        }
        // M2: money engine tables (DATA_MODEL §3.3–3.9).
        migrator.registerMigration("v3_money") { db in try MoneySchema.create(db) }
        // M3: tags and receipts (DATA_MODEL §3.10–3.12).
        migrator.registerMigration("v4_activity") { db in try ActivitySchema.create(db) }
        // M4: budgets (DATA_MODEL §3.13–3.15).
        migrator.registerMigration("v5_budget") { db in try BudgetSchema.create(db) }
        // M5: people, groups, splits and loans (DATA_MODEL §3.13–3.16).
        migrator.registerMigration("v6_people") { db in try PeopleSchema.create(db) }
        // M6: bills, subscriptions, plans and occurrences (DATA_MODEL §3.17–3.21).
        migrator.registerMigration("v7_recurring") { db in try RecurringSchema.create(db) }
        // 0.6.1: a real account may share a name with a sample account (a real "Hbl" blocked sample "HBL").
        migrator.registerMigration("v8_sample_account_names") { db in
            try db.execute(sql: "DROP INDEX account_name")
            try db.execute(sql: "CREATE UNIQUE INDEX account_name ON account(name_key, is_sample) WHERE deleted_at IS NULL")
        }
        // M7: custom calendar entries (CAL-03).
        migrator.registerMigration("v9_calendar_events") { db in try EventSchema.create(db) }
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
        try safetyCopyBeforeMigrating(pool, into: folder.appendingPathComponent("Safety copies", isDirectory: true))
        return try AppDatabase(pool)
    }

    /// DATA-05: before an update changes the schema of a database that already has data, keep a copy of it
    /// as it was. Only the three newest copies are kept.
    static func safetyCopyBeforeMigrating(_ writer: any DatabaseWriter, into folder: URL, now: Date = Date()) throws {
        let (applied, complete) = try writer.read { db in
            (try migrator.appliedMigrations(db), try migrator.hasCompletedMigrations(db))
        }
        guard !applied.isEmpty, !complete else { return }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        try writer.backup(to: try DatabaseQueue(path: folder.appendingPathComponent("Before update \(stamp).sqlite").path))
        let copies = (try? fileManager.contentsOfDirectory(atPath: folder.path))?.filter { $0.hasPrefix("Before update") }.sorted() ?? []
        for old in copies.dropLast(3) { try? fileManager.removeItem(at: folder.appendingPathComponent(old)) }
    }

    /// Empty in-memory database for tests and previews.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }
}
