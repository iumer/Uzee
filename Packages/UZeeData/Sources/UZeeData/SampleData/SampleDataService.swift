import Foundation
import GRDB

/// Sample mode (DATA-04, PRV-04, DATA_MODEL §3.27): seeds the mockup dataset with `is_sample = 1`
/// and removes it again in one transaction without touching real rows.
public struct SampleDataService: Sendable {
    /// Tables that carry `is_sample`, children before parents so deletes are FK-safe.
    /// Each milestone that adds a user-content table appends it here (M2: accounts, transactions, …).
    public static let defaultTables: [String] = []

    let database: AppDatabase
    let tables: [String]

    public init(database: AppDatabase, tables: [String] = SampleDataService.defaultTables) {
        self.database = database
        self.tables = tables
    }

    /// Turns sample mode on. Seeding the fixture rows arrives with the tables (M2 onwards).
    public func load() throws {
        try database.writer.write { db in
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
