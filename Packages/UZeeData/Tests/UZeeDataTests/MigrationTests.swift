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
        #expect(try db.appliedMigrations() == ["v1_baseline", "v2_device_settings", "v3_money", "v4_activity", "v5_budget", "v6_people", "v7_recurring", "v8_sample_account_names", "v9_calendar_events", "v10_settle_up_loans", "v11_loan_notes", "v12_payment_todos", "v13_todo_due_reminder", "v14_todo_direction", "v15_person_name_resync"])
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
        #expect(try second.appliedMigrations() == ["v1_baseline", "v2_device_settings", "v3_money", "v4_activity", "v5_budget", "v6_people", "v7_recurring", "v8_sample_account_names", "v9_calendar_events", "v10_settle_up_loans", "v11_loan_notes", "v12_payment_todos", "v13_todo_due_reminder", "v14_todo_direction", "v15_person_name_resync"])
        let count = try second.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM settings") }
        #expect(count == 1)
    }

    // A person renamed before v15 gets the new name in generated notes and payee; everything else is left alone.
    @Test("v15 brings a renamed person's loan rows up to date")
    func personNameResync() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v14_todo_direction")
        let person = UUID().uuidString, oldPayee = UUID().uuidString
        let loan = UUID().uuidString, ownNote = UUID().uuidString, expense = UUID().uuidString
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO person (id, created_at, updated_at, display_name, name_key) VALUES (?, 1, 1, 'Test User', 'test user')
                """, arguments: [person])
            try db.execute(sql: """
                INSERT INTO payee (id, created_at, updated_at, name, name_key, use_count) VALUES (?, 1, 1, 'Tset User', 'tset user', 3)
                """, arguments: [oldPayee])
            let insert = """
                INSERT INTO txn (id, created_at, updated_at, kind, occurred_at, local_date, time_zone_id, amount_minor, currency_code,
                    my_share_minor, payee_id, note, counterparty_person_id)
                VALUES (?, 1, 1, ?, 1, '2026-10-01', 'Asia/Karachi', 500000, 'PKR', 500000, ?, ?, ?)
                """
            try db.execute(sql: insert, arguments: [loan, "loanOut", oldPayee, "Lent to Tset User", person])
            try db.execute(sql: insert, arguments: [ownNote, "repayment", oldPayee, "Cash for rent", person])
            try db.execute(sql: insert, arguments: [expense, "expense", oldPayee, "Lent to Tset User", nil])
        }
        _ = try AppDatabase(queue)
        let (rows, payees, newKey, newUse, oldUse) = try queue.read { db in
            func note(_ id: String) throws -> String? { try String.fetchOne(db, sql: "SELECT note FROM txn WHERE id = ?", arguments: [id]) }
            func payee(_ id: String) throws -> String? {
                try String.fetchOne(db, sql: "SELECT p.name FROM txn t JOIN payee p ON p.id = t.payee_id WHERE t.id = ?", arguments: [id])
            }
            return ([try note(loan), try note(ownNote), try note(expense)], [try payee(loan), try payee(ownNote), try payee(expense)],
                    try String.fetchOne(db, sql: "SELECT name_key FROM payee WHERE name = 'Test User'"),
                    try Int.fetchOne(db, sql: "SELECT use_count FROM payee WHERE name = 'Test User'"),
                    try Int.fetchOne(db, sql: "SELECT use_count FROM payee WHERE id = ?", arguments: [oldPayee]))
        }
        #expect(rows == ["Lent to Test User", "Cash for rent", "Lent to Tset User"])
        #expect(payees == ["Test User", "Test User", "Tset User"])
        #expect(newKey == "test user")
        #expect(newUse == 0)
        #expect(oldUse == 3)
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
