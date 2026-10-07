import Foundation
import GRDB

/// Reads and writes the single `device_settings` row (DATA_MODEL §3.2). Not synced.
public struct DeviceSettingsStore: Sendable {
    /// The row always uses this id, so there is exactly one.
    static let rowID = "device"

    let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func isSampleModeActive() throws -> Bool {
        try database.writer.read { db in try Self.sampleModeActive(db) }
    }

    public func setSampleModeActive(_ active: Bool) throws {
        try database.writer.write { db in try Self.setSampleModeActive(active, db) }
    }

    static func sampleModeActive(_ db: Database) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT sample_mode_active FROM device_settings WHERE id = ?", arguments: [rowID]) ?? false
    }

    static func setSampleModeActive(_ active: Bool, _ db: Database) throws {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        try db.execute(sql: """
            INSERT INTO device_settings (id, sample_mode_active, updated_at) VALUES (?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET sample_mode_active = excluded.sample_mode_active, updated_at = excluded.updated_at
            """, arguments: [rowID, active, now])
    }
}
