import Foundation
import GRDB

/// M7 custom calendar entries (CAL-03). Reminder preferences live in `settings` under "reminders" as JSON.
enum EventSchema {
    static func create(_ db: Database) throws {
        try db.create(table: "calendar_event") { t in
            MoneySchema.standardColumns(t)
            t.column("title", .text).notNull()
            t.column("event_date", .text).notNull()
            t.column("minute_of_day", .integer)
            t.column("repeat_unit", .text)
            t.column("amount_minor", .integer)
            t.column("currency_code", .text).references("currency")
            t.column("note", .text)
            t.column("remind_days_before", .integer)
        }
        try db.execute(sql: "CREATE INDEX calendar_event_date ON calendar_event(event_date)")
    }
}
