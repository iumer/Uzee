import Foundation
import GRDB
import UZeeCore

/// Custom calendar entries and reminder preferences (CAL-03, CAL-04).
public struct EventStore: Sendable {
    public enum Problem: Error, Equatable, Sendable { case notFound }

    let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func events() throws -> [CalendarEvent] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM calendar_event WHERE deleted_at IS NULL ORDER BY event_date, minute_of_day")
                .compactMap { row in
                    guard let id = UUID(uuidString: row["id"]), let date = LocalDate(row["event_date"] as String) else { return nil }
                    let minor: Int64? = row["amount_minor"]
                    let code: String? = row["currency_code"]
                    let amount = minor.flatMap { m in code.flatMap(Currency.known(code:)).map { Money(minorUnits: m, currency: $0) } }
                    let unit: String? = row["repeat_unit"]
                    return CalendarEvent(id: id, title: row["title"], date: date, minuteOfDay: row["minute_of_day"],
                                         repeatUnit: unit.flatMap(RecurrenceUnit.init(rawValue:)), amount: amount, note: row["note"],
                                         remindDaysBefore: row["remind_days_before"], isSample: (row["is_sample"] as Int64) == 1)
                }
        }
    }

    /// Inserts or updates an event.
    public func save(_ event: CalendarEvent) throws {
        try event.validate()
        try database.writer.write { db in
            let now = Timestamp.now()
            try db.execute(sql: """
                INSERT INTO calendar_event (id, created_at, updated_at, is_sample, title, event_date, minute_of_day, repeat_unit,
                                            amount_minor, currency_code, note, remind_days_before)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at, title = excluded.title, event_date = excluded.event_date,
                    minute_of_day = excluded.minute_of_day, repeat_unit = excluded.repeat_unit, amount_minor = excluded.amount_minor,
                    currency_code = excluded.currency_code, note = excluded.note, remind_days_before = excluded.remind_days_before
                """, arguments: [event.id.uuidString, now, now, event.isSample ? 1 : 0,
                                 event.title.trimmingCharacters(in: .whitespaces), event.date.description, event.minuteOfDay,
                                 event.repeatUnit?.rawValue, event.amount?.minorUnits, event.amount?.currency.code,
                                 event.note.flatMap { $0.isEmpty ? nil : $0 }, event.remindDaysBefore])
        }
    }

    public func delete(_ id: UUID) throws {
        try database.writer.write { db in
            let now = Timestamp.now()
            try db.execute(sql: "UPDATE calendar_event SET deleted_at = ?, deletion_batch_id = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL",
                           arguments: [now, UUID().uuidString, now, id.uuidString])
            guard db.changesCount == 1 else { throw Problem.notFound }
        }
    }

    public func reminderSettings() throws -> ReminderSettings {
        try database.writer.read { db in
            guard let json = try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = 'reminders'"),
                  let settings = try? JSONDecoder().decode(ReminderSettings.self, from: Data(json.utf8)) else { return .standard }
            return settings
        }
    }

    public func setReminderSettings(_ settings: ReminderSettings) throws {
        let json = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        try database.writer.write { db in
            let now = Date()
            try db.execute(sql: """
                INSERT INTO settings (id, key, value, createdAt, updatedAt) VALUES (?, 'reminders', ?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt
                """, arguments: [UUID().uuidString, json, now, now])
        }
    }
}
