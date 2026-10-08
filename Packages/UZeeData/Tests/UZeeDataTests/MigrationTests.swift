import Foundation
import Testing
import GRDB
@testable import UZeeData

@Suite("Migrations")
struct MigrationTests {
    // SMK-004 (unit part) / ENV-004: an empty database is migrated to the latest version.
    @Test("Empty database gets every migration")
    func baseline() throws {
        let db = try AppDatabase.inMemory()
        #expect(try db.appliedMigrations() == ["v1_baseline", "v2_device_settings", "v3_money", "v4_activity", "v5_budget", "v6_people", "v7_recurring", "v8_sample_account_names", "v9_calendar_events"])
        #expect(try db.isUpToDate())
        let hasSettings = try db.writer.read { try $0.tableExists("settings") }
        #expect(hasSettings)
    }

    // ENV-004: reopening a migrated database applies nothing new and keeps data.
    @Test("Second open applies nothing and keeps rows")
    func reopenIsIdempotent() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("uzee-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let first = try AppDatabase(DatabaseQueue(path: path))
            try first.writer.write { db in
                try db.execute(sql: "INSERT INTO settings (id, key, value, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?)",
                               arguments: [UUID().uuidString, "baseCurrency", "PKR", Date(), Date()])
            }
        }
        let second = try AppDatabase(DatabaseQueue(path: path))
        #expect(try second.appliedMigrations() == ["v1_baseline", "v2_device_settings", "v3_money", "v4_activity", "v5_budget", "v6_people", "v7_recurring", "v8_sample_account_names", "v9_calendar_events"])
        let count = try second.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM settings") }
        #expect(count == 1)
    }

    // DATA-05: an older database gets a safety copy before the update migrates it; a new or current one doesn't.
    @Test("Safety copy before migrating older data")
    func safetyCopy() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("uzee-safety-\(UUID().uuidString)")
        let old = try DatabaseQueue()
        var partial = DatabaseMigrator()
        partial.registerMigration("v1_baseline") { db in
            try db.create(table: "settings") { t in
                t.primaryKey("id", .text)
                t.column("key", .text).notNull().unique()
                t.column("value", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }
        try partial.migrate(old)
        try AppDatabase.safetyCopyBeforeMigrating(old, into: folder)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 1)
        let current = try AppDatabase.inMemory()
        try AppDatabase.safetyCopyBeforeMigrating(current.writer, into: folder)
        try AppDatabase.safetyCopyBeforeMigrating(try DatabaseQueue(), into: folder)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 1)
        _ = try AppDatabase(old)
    }

    @Test("Settings keys are unique")
    func uniqueKey() throws {
        let db = try AppDatabase.inMemory()
        let insert = "INSERT INTO settings (id, key, value, createdAt, updatedAt) VALUES (?, 'k', 'v', ?, ?)"
        try db.writer.write { try $0.execute(sql: insert, arguments: [UUID().uuidString, Date(), Date()]) }
        #expect(throws: (any Error).self) {
            try db.writer.write { try $0.execute(sql: insert, arguments: [UUID().uuidString, Date(), Date()]) }
        }
    }
}
