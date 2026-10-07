import Foundation

/// Repeat unit (DATA_MODEL §3.19). Raw values are stored.
public enum RecurrenceUnit: String, CaseIterable, Sendable, Codable {
    case day, week, month, year
}

/// When an item repeats: every `interval` units from `anchor` (the first due date), optionally until
/// `end` or for `limit` times. Months keep the anchor's day, clamped to short months (31st → 30 Apr,
/// 29 Feb → 28 Feb), and never drift (REC-01).
public struct RecurrenceRule: Hashable, Sendable {
    public var unit: RecurrenceUnit
    public var interval: Int
    public var anchor: LocalDate
    public var end: LocalDate?
    public var limit: Int?

    public init(unit: RecurrenceUnit = .month, interval: Int = 1, anchor: LocalDate, end: LocalDate? = nil, limit: Int? = nil) {
        self.unit = unit
        self.interval = max(1, interval)
        self.anchor = anchor
        self.end = end
        self.limit = limit
    }

    /// The date of occurrence `index` (0 = the anchor), or nil past the end or limit.
    public func date(at index: Int) -> LocalDate? {
        guard index >= 0 else { return nil }
        if let limit, index >= limit { return nil }
        let date: LocalDate
        switch unit {
        case .day: date = anchor.addingDays(index * interval)
        case .week: date = anchor.addingDays(index * interval * 7)
        case .month: date = anchor.addingMonths(index * interval)
        case .year: date = anchor.addingMonths(index * interval * 12)
        }
        if let end, date > end { return nil }
        return date
    }

    /// The index of the first occurrence on or after `date`.
    public func firstIndex(onOrAfter date: LocalDate) -> Int {
        guard date > anchor else { return 0 }
        var guess: Int
        switch unit {
        case .day: guess = anchor.days(to: date) / interval
        case .week: guess = anchor.days(to: date) / (interval * 7)
        case .month: guess = ((date.year - anchor.year) * 12 + date.month - anchor.month) / interval
        case .year: guess = (date.year - anchor.year) / interval
        }
        guess = max(0, guess - 1)
        while let candidate = self.date(at: guess), candidate < date { guess += 1 }
        return guess
    }

    /// Dates in `from...through`, with their indexes.
    public func occurrences(from: LocalDate, through: LocalDate) -> [(index: Int, date: LocalDate)] {
        var result: [(Int, LocalDate)] = []
        var index = firstIndex(onOrAfter: from)
        while let date = date(at: index), date <= through {
            result.append((index, date))
            index += 1
            if result.count > 5_000 { break }
        }
        return result
    }

    /// "Every month", "Every 3 months", "Every week", "Every year".
    public var text: String {
        let names: [RecurrenceUnit: (String, String)] = [.day: ("day", "days"), .week: ("week", "weeks"), .month: ("month", "months"), .year: ("year", "years")]
        let (one, many) = names[unit] ?? ("month", "months")
        if unit == .month && interval == 3 { return "Every quarter" }
        return interval == 1 ? "Every \(one)" : "Every \(interval) \(many)"
    }

    /// Times per year as a fraction (numerator, denominator), for monthly and yearly totals.
    var perYear: (Int64, Int64) {
        switch unit {
        case .day: (365, Int64(interval))
        case .week: (52, Int64(interval))
        case .month: (12, Int64(interval))
        case .year: (1, Int64(interval))
        }
    }
}

/// Kinds of recurring item (REC-01). Raw values are stored.
public enum RecurringType: String, CaseIterable, Sendable, Codable {
    case bill, rent, utility, salary, insurance, membership, subscription, income, installment, kameti, other

    public var name: String {
        switch self {
        case .bill: "Bill"
        case .rent: "Rent"
        case .utility: "Utility"
        case .salary: "Salary"
        case .insurance: "Insurance"
        case .membership: "Membership"
        case .subscription: "Subscription"
        case .income: "Income"
        case .installment: "Installment"
        case .kameti: "Kameti"
        case .other: "Other"
        }
    }

    public var isIncome: Bool { self == .salary || self == .income }
    public var isPlan: Bool { self == .installment || self == .kameti }

    /// The transaction kind posted when it is marked paid.
    public var transactionKind: TransactionKind {
        switch self {
        case .salary, .income: .income
        case .installment: .installment
        case .kameti: .kametiContribution
        default: .expense
        }
    }
}

public enum SubscriptionStatus: String, CaseIterable, Sendable, Codable {
    case active, paused, cancelled

    public var name: String {
        switch self {
        case .active: "Active"
        case .paused: "Paused"
        case .cancelled: "Cancelled"
        }
    }
}

public struct PricePoint: Hashable, Sendable {
    public var effectiveFrom: LocalDate
    public var amount: Money

    public init(effectiveFrom: LocalDate, amount: Money) {
        self.effectiveFrom = effectiveFrom
        self.amount = amount
    }
}

/// A kameti payout, expected or received (KAM-01/04).
public struct KametiPayout: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var expectedDate: LocalDate
    public var amount: Money
    public var transactionID: UUID?

    public init(id: UUID = UUID(), expectedDate: LocalDate, amount: Money, transactionID: UUID? = nil) {
        self.id = id
        self.expectedDate = expectedDate
        self.amount = amount
        self.transactionID = transactionID
    }

    public var isReceived: Bool { transactionID != nil }
}

/// A bill, subscription, income, installment plan or kameti (DATA_MODEL §3.17–3.19). Installment and
/// kameti plans are recurring items with a `limit` and `paidBeforeTracking` (REC-07, LOAN-06, KAM-01).
public struct RecurringItem: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var type: RecurringType
    /// Current amount (the latest price).
    public var amount: Money
    public var isEstimated: Bool
    public var accountID: UUID?
    public var categoryID: UUID?
    /// Split equally with this group when posted; `paidByID` nil means you pay.
    public var groupID: UUID?
    public var paidByID: UUID?
    public var rule: RecurrenceRule
    /// Occurrences before this day happened before UZee tracked them and never show as due.
    public var trackedFrom: LocalDate
    /// Installments or contributions already paid before tracking (car: 14).
    public var paidBeforeTracking: Int
    public var status: SubscriptionStatus
    public var statusChangedAt: LocalDate?
    public var startedOn: LocalDate?
    public var colorHex: String
    public var priceHistory: [PricePoint]
    public var payouts: [KametiPayout]
    public var notes: String?
    public var isSample: Bool

    public init(id: UUID = UUID(), name: String, type: RecurringType, amount: Money, isEstimated: Bool = false,
                accountID: UUID? = nil, categoryID: UUID? = nil, groupID: UUID? = nil, paidByID: UUID? = nil,
                rule: RecurrenceRule, trackedFrom: LocalDate? = nil, paidBeforeTracking: Int = 0, status: SubscriptionStatus = .active,
                statusChangedAt: LocalDate? = nil, startedOn: LocalDate? = nil, colorHex: String = "#8E8E93",
                priceHistory: [PricePoint] = [], payouts: [KametiPayout] = [], notes: String? = nil, isSample: Bool = false) {
        self.id = id
        self.name = name
        self.type = type
        self.amount = amount
        self.isEstimated = isEstimated
        self.accountID = accountID
        self.categoryID = categoryID
        self.groupID = groupID
        self.paidByID = paidByID
        self.rule = rule
        self.trackedFrom = trackedFrom ?? rule.anchor
        self.paidBeforeTracking = paidBeforeTracking
        self.status = status
        self.statusChangedAt = statusChangedAt
        self.startedOn = startedOn
        self.colorHex = colorHex
        self.priceHistory = priceHistory
        self.payouts = payouts
        self.notes = notes
        self.isSample = isSample
    }

    /// Paused and cancelled items make no new occurrences (REC-03).
    public var isActive: Bool { status == .active }

    /// The price in effect on `date` (REC-03 price history), else the current amount.
    public func amount(on date: LocalDate) -> Money {
        priceHistory.filter { $0.effectiveFrom <= date }.max { $0.effectiveFrom < $1.effectiveFrom }?.amount ?? amount
    }

    public enum Problem: Error, Equatable, Sendable {
        case emptyName
        case invalidAmount
        case invalidRule
    }

    public func validate() throws(Problem) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw .emptyName }
        guard amount.minorUnits > 0 else { throw .invalidAmount }
        guard rule.interval >= 1, rule.interval <= 365, (rule.limit ?? 1) >= 1 else { throw .invalidRule }
        if let end = rule.end, end < rule.anchor { throw .invalidRule }
    }
}

public enum OccurrenceStatus: String, CaseIterable, Sendable, Codable {
    case scheduled, paid, skipped, snoozed
}

/// What happened to one occurrence (only resolved or moved occurrences are stored).
public struct OccurrenceRecord: Hashable, Sendable {
    public var itemID: UUID
    public var scheduledDate: LocalDate
    public var status: OccurrenceStatus
    public var snoozedUntil: LocalDate?
    public var transactionID: UUID?

    public init(itemID: UUID, scheduledDate: LocalDate, status: OccurrenceStatus, snoozedUntil: LocalDate? = nil, transactionID: UUID? = nil) {
        self.itemID = itemID
        self.scheduledDate = scheduledDate
        self.status = status
        self.snoozedUntil = snoozedUntil
        self.transactionID = transactionID
    }
}

/// Display state (CAL-02).
public enum OccurrenceState: String, Sendable {
    case paid, skipped, overdue, dueToday, upcoming

    public var name: String {
        switch self {
        case .paid: "Paid"
        case .skipped: "Skipped"
        case .overdue: "Overdue"
        case .dueToday: "Due today"
        case .upcoming: "Upcoming"
        }
    }
}

/// One due date of an item, with its state.
public struct Occurrence: Hashable, Sendable, Identifiable {
    public var itemID: UUID
    /// 1-based (installment 15 of 36).
    public var sequence: Int
    public var scheduledDate: LocalDate
    /// Scheduled date, or the snoozed date.
    public var dueDate: LocalDate
    public var amount: Money
    public var state: OccurrenceState
    public var transactionID: UUID?

    public var id: String { "\(itemID.uuidString)|\(scheduledDate)" }
    public var isResolved: Bool { state == .paid || state == .skipped }
}

/// Builds occurrences from rules and records (REC-02, REC-08).
public enum OccurrenceGenerator {
    /// Occurrences scheduled in `from...through` (plus earlier unresolved ones when `includeOverdue`).
    public static func occurrences(_ item: RecurringItem, records: [OccurrenceRecord], from: LocalDate, through: LocalDate,
                                   today: LocalDate, includeOverdue: Bool = false) -> [Occurrence] {
        let byDate = Dictionary(records.filter { $0.itemID == item.id }.map { ($0.scheduledDate, $0) }, uniquingKeysWith: { a, _ in a })
        let start = includeOverdue ? min(from, item.trackedFrom) : from
        var result: [Occurrence] = []
        for (index, date) in item.rule.occurrences(from: start, through: through) {
            let sequence = index + 1
            let record = byDate[date]
            let preTracked = sequence <= item.paidBeforeTracking || date < item.trackedFrom
            if preTracked && date < from { continue }
            let due = record?.status == .snoozed ? (record?.snoozedUntil ?? date) : date
            let state: OccurrenceState
            switch record?.status {
            case .paid: state = .paid
            case .skipped: state = .skipped
            default:
                if preTracked { state = .paid } else if !item.isActive { continue }
                else { state = due < today ? .overdue : due == today ? .dueToday : .upcoming }
            }
            if date < from && (state == .paid || state == .skipped) { continue }
            result.append(Occurrence(itemID: item.id, sequence: sequence, scheduledDate: date, dueDate: due,
                                     amount: item.amount(on: date), state: state, transactionID: record?.transactionID))
        }
        return result.sorted { $0.dueDate < $1.dueDate }
    }

    /// The earliest occurrence still to pay (overdue first), or nil when nothing is left.
    public static func next(_ item: RecurringItem, records: [OccurrenceRecord], today: LocalDate) -> Occurrence? {
        guard item.isActive else { return nil }
        let horizon = today.addingMonths(item.rule.unit == .year ? 13 * item.rule.interval : 2 * max(1, item.rule.interval) + 1)
        return occurrences(item, records: records, from: today, through: horizon, today: today, includeOverdue: true)
            .first { !$0.isResolved }
    }

    /// Paid count including those before tracking (installment and kameti progress).
    public static func paidCount(_ item: RecurringItem, records: [OccurrenceRecord]) -> Int {
        let paidRecords = records.filter { record in
            guard record.itemID == item.id, record.status == .paid else { return false }
            let index = item.rule.firstIndex(onOrAfter: record.scheduledDate)
            return index + 1 > item.paidBeforeTracking
        }
        return min(item.rule.limit ?? Int.max, item.paidBeforeTracking + paidRecords.count)
    }
}

/// Monthly and yearly totals in base (REC-04), my share only for split items.
public enum RecurringTotals {
    /// Monthly equivalent in base: amount × times-per-year ÷ 12, half-up once; my share when split equally.
    public static func monthly(_ item: RecurringItem, myShareDivisor: Int64 = 1, base: Currency, rates: [String: Decimal]) -> Money {
        let (times, per) = item.rule.perYear
        let value = item.amount.decimalValue * Decimal(times) / Decimal(per) / 12 / Decimal(max(1, myShareDivisor))
        let local = (try? Money.fromMajor(value, item.amount.currency)) ?? .zero(item.amount.currency)
        return (try? RateTable.toBase(local, base: base, rates: rates)) ?? .zero(base)
    }
}

/// Kameti progress (KAM-04).
public struct KametiSummary: Hashable, Sendable {
    public var paid: Int
    public var total: Int
    public var contributed: Money
    public var totalContributions: Money
    public var payouts: Money
    /// Payouts don't add up to contributions: "Check figures with the committee" (AS-04).
    public var mismatch: Bool

    public init(_ item: RecurringItem, records: [OccurrenceRecord]) {
        total = item.rule.limit ?? 0
        paid = OccurrenceGenerator.paidCount(item, records: records)
        let currency = item.amount.currency
        contributed = Money(minorUnits: item.amount.minorUnits &* Int64(paid), currency: currency)
        totalContributions = Money(minorUnits: item.amount.minorUnits &* Int64(total), currency: currency)
        payouts = Money(minorUnits: item.payouts.reduce(Int64(0)) { $0 &+ $1.amount.minorUnits }, currency: currency)
        mismatch = !item.payouts.isEmpty && payouts != totalContributions
    }
}

/// Installment plan progress (LOAN-06).
public struct InstallmentSummary: Hashable, Sendable {
    public var paid: Int
    public var total: Int
    public var remaining: Money
    public var endDate: LocalDate?

    public init(_ item: RecurringItem, records: [OccurrenceRecord]) {
        total = item.rule.limit ?? 0
        paid = OccurrenceGenerator.paidCount(item, records: records)
        remaining = Money(minorUnits: item.amount.minorUnits &* Int64(max(0, total - paid)), currency: item.amount.currency)
        endDate = total > 0 ? item.rule.date(at: total - 1) : nil
    }

    public var left: Int { max(0, total - paid) }
}

/// Everything the Bills hub and Calendar read.
public struct RecurringSnapshot: Sendable {
    public var items: [RecurringItem]
    public var records: [OccurrenceRecord]

    public init(items: [RecurringItem], records: [OccurrenceRecord]) {
        self.items = items
        self.records = records
    }

    public static let empty = RecurringSnapshot(items: [], records: [])

    public func item(_ id: UUID?) -> RecurringItem? { items.first { $0.id == id } }
    public func records(for item: UUID) -> [OccurrenceRecord] { records.filter { $0.itemID == item } }
    public func next(_ item: RecurringItem, today: LocalDate) -> Occurrence? {
        OccurrenceGenerator.next(item, records: records(for: item.id), today: today)
    }
}
