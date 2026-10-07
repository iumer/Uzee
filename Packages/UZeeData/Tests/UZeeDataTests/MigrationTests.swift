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
        #expect(try db.appliedMigrations() == ["v1_baseline", "v2_device_settings", "v3_money"])
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
        #expect(try second.appliedMigrations() == ["v1_baseline", "v2_device_settings", "v3_money"])
        let count = try second.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM settings") }
        #expect(count == 1)
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
