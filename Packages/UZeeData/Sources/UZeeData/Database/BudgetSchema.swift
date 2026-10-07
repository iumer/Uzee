import Foundation
import GRDB

/// M4 tables: budget settings, one budget per period with its category limits, and fired alerts
/// (DATA_MODEL §3.13–3.15).
enum BudgetSchema {
    static func create(_ db: Database) throws {
        try db.create(table: "budget_settings") { t in
            t.primaryKey("id", .text)
            t.column("period_kind", .text).notNull().defaults(to: "month")
            t.column("warn_percent", .integer).notNull().defaults(to: 80).check { $0 >= 50 && $0 <= 100 }
            t.column("updated_at", .integer).notNull()
        }
        try db.execute(sql: "INSERT INTO budget_settings (id, period_kind, warn_percent, updated_at) VALUES ('main', 'month', 80, ?)",
                       arguments: [Timestamp.now()])

        try db.create(table: "budget") { t in
            MoneySchema.standardColumns(t)
            t.column("period_start", .text).notNull()
            t.column("total_minor", .integer).notNull().check { $0 >= 0 }
            t.column("currency_code", .text).notNull().references("currency")
        }
        try db.execute(sql: "CREATE UNIQUE INDEX budget_period ON budget(period_start, is_sample) WHERE deleted_at IS NULL")

        try db.create(table: "budget_limit") { t in
            MoneySchema.standardColumns(t)
            t.column("budget_id", .text).notNull().references("budget", onDelete: .cascade)
            t.column("category_id", .text).notNull().references("category", onDelete: .cascade)
            t.column("limit_minor", .integer).notNull().check { $0 >= 0 }
        }
        try db.execute(sql: "CREATE UNIQUE INDEX budget_limit_category ON budget_limit(budget_id, category_id)")

        try db.create(table: "budget_alert") { t in
            t.primaryKey("key", .text)
            t.column("fired_at", .integer).notNull()
        }
    }
}
