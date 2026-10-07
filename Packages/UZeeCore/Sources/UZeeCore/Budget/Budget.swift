import Foundation

/// How budget periods are cut (BUD-02): calendar month by default, or a salary cycle from a start day.
public enum BudgetPeriodKind: Hashable, Sendable {
    case calendarMonth
    /// Starts on `startDay` (1…31, clamped to short months) and ends the day before the next start.
    case salaryCycle(startDay: Int)

    public var storageValue: String {
        switch self {
        case .calendarMonth: "month"
        case .salaryCycle(let day): "salary:\(day)"
        }
    }

    public init(storage: String) {
        if storage.hasPrefix("salary:"), let day = Int(storage.dropFirst(7)), (1...31).contains(day) {
            self = .salaryCycle(startDay: day)
        } else {
            self = .calendarMonth
        }
    }
}

/// One budget period, inclusive on both ends.
public struct BudgetPeriod: Hashable, Sendable, Identifiable {
    public let start: LocalDate
    public let end: LocalDate
    public let kind: BudgetPeriodKind
    public var id: LocalDate { start }

    public init(start: LocalDate, end: LocalDate, kind: BudgetPeriodKind) {
        self.start = start
        self.end = end
        self.kind = kind
    }

    /// The period that contains `date`.
    public static func containing(_ date: LocalDate, kind: BudgetPeriodKind) -> BudgetPeriod {
        switch kind {
        case .calendarMonth:
            return BudgetPeriod(start: date.firstOfMonth, end: date.lastOfMonth, kind: kind)
        case .salaryCycle(let startDay):
            let thisMonthStart = cycleStart(year: date.year, month: date.month, startDay: startDay)
            let start = date >= thisMonthStart ? thisMonthStart : cycleStart(of: date.firstOfMonth.addingMonths(-1), startDay: startDay)
            let next = cycleStart(of: start.firstOfMonth.addingMonths(1), startDay: startDay)
            return BudgetPeriod(start: start, end: next.addingDays(-1), kind: kind)
        }
    }

    public var next: BudgetPeriod { Self.containing(end.addingDays(1), kind: kind) }
    public var previous: BudgetPeriod { Self.containing(start.addingDays(-1), kind: kind) }

    public func contains(_ date: LocalDate) -> Bool { date >= start && date <= end }

    /// Days in the period, and how many have passed by `today` (for "same point last month").
    public var length: Int { start.days(to: end) + 1 }

    private static func cycleStart(year: Int, month: Int, startDay: Int) -> LocalDate {
        LocalDate(year: year, month: month, day: min(startDay, LocalDate.daysIn(year: year, month: month)))
    }

    private static func cycleStart(of firstOfMonth: LocalDate, startDay: Int) -> LocalDate {
        cycleStart(year: firstOfMonth.year, month: firstOfMonth.month, startDay: startDay)
    }
}

/// The plan for one period: a total and limits per category (BUD-01, BUD-03). Amounts in base currency.
public struct BudgetPlan: Hashable, Sendable {
    public var periodStart: LocalDate
    public var total: Money
    /// Category id (a top-level group or a subcategory) → limit.
    public var limits: [UUID: Money]

    public init(periodStart: LocalDate, total: Money, limits: [UUID: Money] = [:]) {
        self.periodStart = periodStart
        self.total = total
        self.limits = limits
    }
}

/// How full a budget line is.
public enum BudgetState: Hashable, Sendable {
    case onTrack, warning, over
}

/// One category row on the Budget screen.
public struct BudgetLine: Hashable, Sendable, Identifiable {
    public var categoryID: UUID
    public var limit: Money
    public var spent: Money
    public var id: UUID { categoryID }

    public var remaining: Money { (try? limit.subtracting(spent)) ?? limit }
    public var overBy: Money? {
        guard let left = try? limit.subtracting(spent), left.isNegative else { return nil }
        return try? left.negated()
    }
    /// Spent ÷ limit in basis points, half-up (10000 = 100%).
    public var usedBasisPoints: Int { BudgetCalculator.basisPoints(spent, of: limit) }

    public func state(warnPercent: Int) -> BudgetState {
        if spent.minorUnits > limit.minorUnits { return .over }
        return usedBasisPoints >= warnPercent * 100 && limit.minorUnits > 0 ? .warning : .onTrack
    }
}

/// Everything the Budget screen shows for one period.
public struct BudgetSummary: Hashable, Sendable {
    public var period: BudgetPeriod
    public var total: Money
    public var spent: Money
    public var lines: [BudgetLine]
    /// Spending in categories that have no limit (e.g. Health in September).
    public var unbudgeted: [UUID: Money]

    public var left: Money { (try? total.subtracting(spent)) ?? total }
    public var usedBasisPoints: Int { BudgetCalculator.basisPoints(spent, of: total) }
    public var assigned: Money { (try? Money.sum(lines.map(\.limit), in: total.currency)) ?? total }
    /// Total − sum of limits; negative when limits exceed the total.
    public var unassigned: Money { (try? total.subtracting(assigned)) ?? .zero(total.currency) }
    public var isOver: Bool { spent.minorUnits > total.minorUnits }
}

/// Budget arithmetic (BUD-04…07). Spending is my share, in base currency at the table rate; transfers,
/// loans and settle-ups never count (SpendingRules).
public enum BudgetCalculator {
    public static func summary(plan: BudgetPlan, period: BudgetPeriod, transactions: [MoneyTransaction],
                               categories: [SpendCategory], base: Currency, rates: [String: Decimal]) -> BudgetSummary {
        let byCategory = spending(transactions, in: period, base: base, rates: rates)
        let parentOf = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.parentID) })
        var lines: [BudgetLine] = []
        var covered = Set<UUID>()
        // Limits in the category tree's order.
        for category in categories where plan.limits[category.id] != nil {
            let ids = Set([category.id] + categories.filter { $0.parentID == category.id }.map(\.id))
            covered.formUnion(ids)
            let spent = sum(byCategory.filter { ids.contains($0.key) }.map(\.value), base)
            lines.append(BudgetLine(categoryID: category.id, limit: plan.limits[category.id]!, spent: spent))
        }
        var unbudgeted: [UUID: Money] = [:]
        for (id, amount) in byCategory where !covered.contains(id) {
            let group = parentOf[id].flatMap { $0 } ?? id
            if covered.contains(group) { continue }
            unbudgeted[group] = sum([unbudgeted[group] ?? .zero(base), amount], base)
        }
        let spent = sum(Array(byCategory.values), base)
        return BudgetSummary(period: period, total: plan.total, spent: spent, lines: lines, unbudgeted: unbudgeted)
    }

    /// My-share spending per category id within the period (refunds subtract).
    public static func spending(_ transactions: [MoneyTransaction], in period: BudgetPeriod, base: Currency,
                                rates: [String: Decimal]) -> [UUID: Money] {
        var result: [UUID: Money] = [:]
        for transaction in transactions where transaction.isEffective && period.contains(transaction.localDate) {
            let sign = SpendingRules.spendingSign(transaction.kind)
            guard sign != 0, let category = transaction.categoryID,
                  let share = try? RateTable.toBase(transaction.myShare, base: base, rates: rates) else { continue }
            let signed = sign < 0 ? ((try? share.negated()) ?? share) : share
            result[category] = sum([result[category] ?? .zero(base), signed], base)
        }
        return result
    }

    /// Rounded half-up basis points of `part` ÷ `whole`; 0 when `whole` is zero.
    public static func basisPoints(_ part: Money, of whole: Money) -> Int {
        guard whole.minorUnits != 0 else { return 0 }
        let ratio = Decimal(part.minorUnits) * 10_000 / Decimal(whole.minorUnits)
        return Int(Rounding.int64(Rounding.halfUp(ratio, scale: 0)) ?? 0)
    }

    /// "33%" from basis points, half-up to a whole percent.
    public static func percentText(_ basisPoints: Int) -> String {
        "\((basisPoints + 50) / 100)%"
    }

    private static func sum(_ amounts: [Money], _ base: Currency) -> Money {
        (try? Money.sum(amounts, in: base)) ?? .zero(base)
    }
}

/// Fire-once budget alerts (BUD-08): a warning at the threshold and an alert when over, per period
/// and line; re-evaluated after every change, never repeated.
public enum BudgetAlerts {
    public struct Alert: Hashable, Sendable {
        /// Category id, or nil for the whole budget.
        public var categoryID: UUID?
        public var state: BudgetState
        /// Key stored once fired: "2026-10-01|<id or total>|warning".
        public var key: String
    }

    public static func due(_ summary: BudgetSummary, warnPercent: Int, fired: Set<String>) -> [Alert] {
        var alerts: [Alert] = []
        func consider(_ id: UUID?, _ state: BudgetState) {
            guard state != .onTrack else { return }
            let key = "\(summary.period.start)|\(id?.uuidString ?? "total")|\(state == .over ? "over" : "warning")"
            if !fired.contains(key) { alerts.append(Alert(categoryID: id, state: state, key: key)) }
        }
        let totalLine = BudgetLine(categoryID: UUID(), limit: summary.total, spent: summary.spent)
        consider(nil, totalLine.state(warnPercent: warnPercent))
        for line in summary.lines { consider(line.categoryID, line.state(warnPercent: warnPercent)) }
        return alerts
    }
}
