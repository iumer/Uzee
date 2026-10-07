import Foundation
import GRDB
import UZeeCore

/// Budgets per period (BUD-01…09). A period without a budget copies the latest earlier one when first
/// opened, so limits carry over; nothing rolls over (BUD-06). A real budget wins over a sample one.
public struct BudgetStore: Sendable {
    public struct Settings: Hashable, Sendable {
        public var periodKind: BudgetPeriodKind
        public var warnPercent: Int

        public init(periodKind: BudgetPeriodKind = .calendarMonth, warnPercent: Int = 80) {
            self.periodKind = periodKind
            self.warnPercent = warnPercent
        }
    }

    let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func settings() throws -> Settings {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM budget_settings WHERE id = 'main'") else { return Settings() }
            return Settings(periodKind: BudgetPeriodKind(storage: row["period_kind"]), warnPercent: row["warn_percent"])
        }
    }

    public func setSettings(_ settings: Settings) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE budget_settings SET period_kind = ?, warn_percent = ?, updated_at = ? WHERE id = 'main'",
                           arguments: [settings.periodKind.storageValue, min(100, max(50, settings.warnPercent)), Timestamp.now()])
        }
    }

    /// The plan for `period`, copying the latest earlier plan's total and limits when there is none yet.
    /// Nil when no budget was ever set.
    public func plan(for period: BudgetPeriod, base: Currency = .pkr) throws -> BudgetPlan? {
        try database.writer.write { db in
            if let plan = try Self.fetchPlan(db, start: period.start, base: base) { return plan }
            guard let previous = try String.fetchOne(db, sql: """
                SELECT period_start FROM budget WHERE deleted_at IS NULL AND period_start < ?
                ORDER BY period_start DESC, is_sample ASC LIMIT 1
                """, arguments: [period.start.description]).flatMap(LocalDate.init),
                  var plan = try Self.fetchPlan(db, start: previous, base: base) else { return nil }
            plan.periodStart = period.start
            try Self.write(plan, isSample: try Self.isSample(db, start: previous), db)
            return plan
        }
    }

    /// Plans that already exist, without copying (for history).
    public func existingPlans(base: Currency = .pkr) throws -> [LocalDate: BudgetPlan] {
        try database.writer.read { db in
            var plans: [LocalDate: BudgetPlan] = [:]
            for start in try String.fetchAll(db, sql: "SELECT DISTINCT period_start FROM budget WHERE deleted_at IS NULL").compactMap(LocalDate.init) {
                plans[start] = try Self.fetchPlan(db, start: start, base: base)
            }
            return plans
        }
    }

    /// Saves the total and limits for the plan's period as the user's own budget.
    public func save(_ plan: BudgetPlan) throws {
        try database.writer.write { db in try Self.write(plan, isSample: false, db) }
    }

    public func firedAlerts() throws -> Set<String> {
        try database.writer.read { db in Set(try String.fetchAll(db, sql: "SELECT key FROM budget_alert")) }
    }

    public func markFired(_ keys: [String]) throws {
        try database.writer.write { db in
            for key in keys {
                try db.execute(sql: "INSERT OR IGNORE INTO budget_alert (key, fired_at) VALUES (?, ?)", arguments: [key, Timestamp.now()])
            }
        }
    }

    // MARK: Rows

    static func fetchPlan(_ db: Database, start: LocalDate, base: Currency) throws -> BudgetPlan? {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT * FROM budget WHERE period_start = ? AND deleted_at IS NULL ORDER BY is_sample ASC LIMIT 1
            """, arguments: [start.description]) else { return nil }
        let id: String = row["id"]
        let currency = Currency.known(code: row["currency_code"]) ?? base
        var limits: [UUID: Money] = [:]
        for limit in try Row.fetchAll(db, sql: """
            SELECT l.category_id, l.limit_minor FROM budget_limit l JOIN category c ON c.id = l.category_id
            WHERE l.budget_id = ? AND l.deleted_at IS NULL AND c.deleted_at IS NULL
            """, arguments: [id]) {
            if let category = UUID(uuidString: limit["category_id"]) {
                limits[category] = Money(minorUnits: limit["limit_minor"], currency: currency)
            }
        }
        return BudgetPlan(periodStart: start, total: Money(minorUnits: row["total_minor"], currency: currency), limits: limits)
    }

    static func isSample(_ db: Database, start: LocalDate) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT MIN(is_sample) FROM budget WHERE period_start = ? AND deleted_at IS NULL",
                          arguments: [start.description]) ?? false
    }

    /// Replaces the budget row of this period and sample flag, with its limits.
    static func write(_ plan: BudgetPlan, isSample: Bool, _ db: Database) throws {
        let now = Timestamp.now()
        let start = plan.periodStart.description
        let id = try String.fetchOne(db, sql: "SELECT id FROM budget WHERE period_start = ? AND is_sample = ? AND deleted_at IS NULL",
                                     arguments: [start, isSample]) ?? UUID().uuidString
        try db.execute(sql: """
            INSERT INTO budget (id, created_at, updated_at, is_sample, period_start, total_minor, currency_code)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET total_minor = excluded.total_minor, updated_at = excluded.updated_at
            """, arguments: [id, now, now, isSample, start, plan.total.minorUnits, plan.total.currency.code])
        try db.execute(sql: "DELETE FROM budget_limit WHERE budget_id = ?", arguments: [id])
        for (category, limit) in plan.limits where limit.minorUnits > 0 {
            try db.execute(sql: """
                INSERT INTO budget_limit (id, created_at, updated_at, is_sample, budget_id, category_id, limit_minor)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [UUID().uuidString, now, now, isSample, id, category.uuidString, limit.minorUnits])
        }
    }
}
