import Foundation
import GRDB

/// M6 tables: recurring items (bills, subscriptions, income, installment and kameti plans), the occurrences
/// that were paid, skipped or snoozed, price history and kameti payouts (DATA_MODEL §3.17–3.21).
/// Unresolved occurrences are computed from the rule, so only resolved ones are stored; the unique
/// (item, scheduled date) key makes Mark paid idempotent.
enum RecurringSchema {
    static func create(_ db: Database) throws {
        try db.create(table: "recurring_item") { t in
            MoneySchema.standardColumns(t)
            t.column("name", .text).notNull()
            t.column("item_type", .text).notNull()
            t.column("amount_minor", .integer).notNull().check { $0 > 0 }
            t.column("is_estimated", .integer).notNull().defaults(to: 0)
            t.column("currency_code", .text).notNull().references("currency")
            t.column("account_id", .text).references("account", onDelete: .setNull)
            t.column("category_id", .text).references("category", onDelete: .setNull)
            t.column("group_id", .text).references("split_group", onDelete: .setNull)
            t.column("paid_by_person_id", .text).references("person", onDelete: .setNull)
            t.column("rule_unit", .text).notNull().defaults(to: "month")
            t.column("rule_interval", .integer).notNull().defaults(to: 1)
            t.column("anchor_date", .text).notNull()
            t.column("end_date", .text)
            t.column("occurrence_limit", .integer)
            t.column("tracked_from", .text).notNull()
            t.column("paid_before_tracking", .integer).notNull().defaults(to: 0)
            t.column("subscription_status", .text).notNull().defaults(to: "active")
            t.column("status_changed_on", .text)
            t.column("started_on", .text)
            t.column("color_hex", .text).notNull().defaults(to: "#8E8E93")
            t.column("notes", .text)
            t.column("sort_order", .integer).notNull().defaults(to: 0)
        }
        try db.execute(sql: "CREATE INDEX recurring_type ON recurring_item(item_type)")

        try db.create(table: "occurrence") { t in
            MoneySchema.standardColumns(t)
            t.column("recurring_item_id", .text).notNull().references("recurring_item", onDelete: .cascade)
            t.column("scheduled_date", .text).notNull()
            t.column("status", .text).notNull()
            t.column("snoozed_until", .text)
            t.column("txn_id", .text).references("txn", onDelete: .setNull)
            t.column("resolved_at", .integer)
        }
        try db.execute(sql: "CREATE UNIQUE INDEX occurrence_unique ON occurrence(recurring_item_id, scheduled_date)")
        try db.execute(sql: "CREATE INDEX occurrence_txn ON occurrence(txn_id)")

        try db.create(table: "price_history") { t in
            MoneySchema.standardColumns(t)
            t.column("recurring_item_id", .text).notNull().references("recurring_item", onDelete: .cascade)
            t.column("effective_from", .text).notNull()
            t.column("amount_minor", .integer).notNull().check { $0 > 0 }
            t.column("currency_code", .text).notNull()
        }
        try db.execute(sql: "CREATE UNIQUE INDEX price_history_unique ON price_history(recurring_item_id, effective_from)")

        try db.create(table: "kameti_payout") { t in
            MoneySchema.standardColumns(t)
            t.column("recurring_item_id", .text).notNull().references("recurring_item", onDelete: .cascade)
            t.column("expected_date", .text).notNull()
            t.column("amount_minor", .integer).notNull().check { $0 > 0 }
            t.column("currency_code", .text).notNull()
            t.column("txn_id", .text).references("txn", onDelete: .setNull)
        }
        try db.execute(sql: "CREATE UNIQUE INDEX kameti_payout_unique ON kameti_payout(recurring_item_id, expected_date)")
    }
}
