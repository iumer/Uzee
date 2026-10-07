import Foundation
import Testing
import GRDB
import UZeeCore
@testable import UZeeData

/// DATA-002 (mechanism) and DATA-003: removing sample data deletes only `is_sample = 1` rows,
/// in one transaction. M1 has no content tables yet, so the tests create stand-in tables.
@Suite("Sample data")
struct SampleDataTests {
    private func makeDatabase() throws -> AppDatabase {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in
            for table in ["sample_parent", "sample_child"] {
                try db.execute(sql: "CREATE TABLE \(table) (id TEXT PRIMARY KEY, is_sample INTEGER NOT NULL DEFAULT 0)")
            }
            try db.execute(sql: "INSERT INTO sample_parent VALUES ('real-1', 0), ('real-2', 0), ('s-1', 1), ('s-2', 1), ('s-3', 1)")
            try db.execute(sql: "INSERT INTO sample_child VALUES ('real-c', 0), ('s-c', 1)")
        }
        return database
    }

    private func count(_ table: String, sample: Bool, in database: AppDatabase) throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table) WHERE is_sample = ?", arguments: [sample]) ?? -1
        }
    }

    @Test("Sample mode starts off and can be turned on")
    func modeFlag() throws {
        let database = try AppDatabase.inMemory()
        let store = DeviceSettingsStore(database: database)
        #expect(try store.isSampleModeActive() == false)
        try SampleDataService(database: database).load()
        #expect(try store.isSampleModeActive() == true)
    }

    @Test("Remove deletes only sample rows and turns the mode off")
    func removeOnlySample() throws {
        let database = try makeDatabase()
        let service = SampleDataService(database: database, tables: ["sample_child", "sample_parent"])
        try service.load()
        let removed = try service.removeAll()
        #expect(removed == 4)
        #expect(try count("sample_parent", sample: true, in: database) == 0)
        #expect(try count("sample_child", sample: true, in: database) == 0)
        #expect(try count("sample_parent", sample: false, in: database) == 2)
        #expect(try count("sample_child", sample: false, in: database) == 1)
        #expect(try DeviceSettingsStore(database: database).isSampleModeActive() == false)
    }

    @Test("A failure part-way removes nothing")
    func allOrNothing() throws {
        let database = try makeDatabase()
        try SampleDataService(database: database).load()
        let service = SampleDataService(database: database, tables: ["sample_parent", "missing_table"])
        #expect(throws: (any Error).self) { try service.removeAll() }
        #expect(try count("sample_parent", sample: true, in: database) == 3)
        #expect(try DeviceSettingsStore(database: database).isSampleModeActive() == true)
    }

    @Test("Settings row stays single when written twice")
    func singleRow() throws {
        let database = try AppDatabase.inMemory()
        let store = DeviceSettingsStore(database: database)
        try store.setSampleModeActive(true)
        try store.setSampleModeActive(false)
        let rows = try database.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM device_settings") }
        #expect(rows == 1)
    }

    // Bug on 0.6.0: a real account named "Hbl" made sample data fail, because sample data has "HBL".
    @Test("Sample data loads beside a real account with the same name")
    func realAccountSameName() throws {
        let database = try AppDatabase.inMemory()
        let ledger = LedgerStore(database: database)
        let real = try ledger.createAccount(name: "Hbl", kind: .bank, currency: .pkr, openingDate: LocalDate(year: 2026, month: 10, day: 1))
        let service = SampleDataService(database: database)
        try service.load()
        let sampleHBL = try database.writer.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM account WHERE name_key = ? AND is_sample = 1", arguments: [NameKey.make("HBL")])
        }
        #expect(sampleHBL == 1)
        _ = try service.removeAll()
        let left = try database.writer.read { try String.fetchAll($0, sql: "SELECT id FROM account") }
        #expect(left == [real.id.uuidString])
        // Two real accounts still can't share a name.
        #expect(throws: LedgerStore.Problem.duplicateName) {
            try ledger.createAccount(name: "HBL", kind: .bank, currency: .pkr, openingDate: LocalDate(year: 2026, month: 10, day: 1))
        }
    }
}
