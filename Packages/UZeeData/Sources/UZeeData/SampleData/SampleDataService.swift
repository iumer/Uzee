import Foundation
import GRDB

/// Sample mode (DATA-04, PRV-04, DATA_MODEL §3.27): seeds the mockup dataset with `is_sample = 1`
/// and removes it again in one transaction without touching real rows.
public struct SampleDataService: Sendable {
    /// Tables that carry `is_sample`, children before parents so deletes are FK-safe.
    /// Each milestone that adds a user-content table appends it here.
    public static let defaultTables: [String] = [
        "occurrence", "price_history", "kameti_payout", "recurring_item",
        "budget_limit", "budget", "attachment", "txn_tag", "tag", "split_share", "split_payer", "split", "loan_payment", "loan",
        "transaction_leg", "txn", "group_member", "split_group", "person", "payee", "account"
    ]

    let database: AppDatabase
    let tables: [String]

    public init(database: AppDatabase, tables: [String] = SampleDataService.defaultTables) {
        self.database = database
        self.tables = tables
    }

    /// Turns sample mode on and seeds the mockup dataset once, all in one transaction.
    public func load() throws {
        try database.writer.write { db in
            let seeded = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM account WHERE is_sample = 1") ?? 0
            if seeded == 0 { try SampleFixture.insert(db) }
            try DeviceSettingsStore.setSampleModeActive(true, db)
        }
    }

    /// Deletes every `is_sample = 1` row and turns sample mode off, all or nothing.
    /// Hard delete: sample rows never go to Recently Deleted. Returns the number of rows removed.
    @discardableResult
    public func removeAll() throws -> Int {
        try database.writer.write { db in
            var removed = 0
            for table in tables {
                try db.execute(sql: "DELETE FROM \(table.quotedDatabaseIdentifier) WHERE is_sample = 1")
                removed += db.changesCount
            }
            try DeviceSettingsStore.setSampleModeActive(false, db)
            return removed
        }
    }
}
