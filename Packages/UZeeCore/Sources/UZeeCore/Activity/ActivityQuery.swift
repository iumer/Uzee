import Foundation

/// A user-defined label on transactions (CAT-006). Not named `Tag` to stay clear of Apple SDK names.
public struct MoneyTag: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var isSample: Bool

    public init(id: UUID = UUID(), name: String, isSample: Bool = false) {
        self.id = id
        self.name = name
        self.isSample = isSample
    }
}

/// Activity filters (PRD ACT-02). Empty sets mean "any".
public struct ActivityFilter: Hashable, Sendable {
    public var accountIDs: Set<UUID> = []
    /// A top-level category also matches its subcategories.
    public var categoryIDs: Set<UUID> = []
    public var kinds: Set<TransactionKind> = []
    public var tagIDs: Set<UUID> = []
    public var from: LocalDate?
    public var through: LocalDate?
    public var text: String = ""

    public init(accountIDs: Set<UUID> = [], categoryIDs: Set<UUID> = [], kinds: Set<TransactionKind> = [],
                tagIDs: Set<UUID> = [], from: LocalDate? = nil, through: LocalDate? = nil, text: String = "") {
        self.accountIDs = accountIDs
        self.categoryIDs = categoryIDs
        self.kinds = kinds
        self.tagIDs = tagIDs
        self.from = from
        self.through = through
        self.text = text
    }

    /// True when any filter or search narrows the list (drives "No results for …" vs the empty state).
    public var isActive: Bool {
        !accountIDs.isEmpty || !categoryIDs.isEmpty || !kinds.isEmpty || !tagIDs.isEmpty || from != nil || through != nil
            || !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Number of filters (not search) in use, for the filter button badge.
    public var count: Int {
        [!accountIDs.isEmpty, !categoryIDs.isEmpty, !kinds.isEmpty, !tagIDs.isEmpty, from != nil || through != nil]
            .filter { $0 }.count
    }
}

/// One day in Activity: its rows (newest first) and the day's spending, my share (TXN-020).
public struct ActivityDay: Hashable, Sendable, Identifiable {
    public var date: LocalDate
    public var transactions: [MoneyTransaction]
    public var spending: Money
    public var id: LocalDate { date }
}

/// Filtering, search and day grouping for Activity. Pure, so it runs in Linux tests.
public enum ActivityQuery {
    /// Rows that match `filter`, newest first. Deleted rows never match.
    public static func filter(_ transactions: [MoneyTransaction], _ filter: ActivityFilter, snapshot: LedgerSnapshot,
                              tags: [UUID: Set<UUID>] = [:]) -> [MoneyTransaction] {
        let categories = expandedCategories(filter.categoryIDs, in: snapshot.categories)
        let search = SearchTerm(filter.text)
        return transactions.filter { transaction in
            guard transaction.deletedAt == nil else { return false }
            if let from = filter.from, transaction.localDate < from { return false }
            if let through = filter.through, transaction.localDate > through { return false }
            if !filter.kinds.isEmpty && !filter.kinds.contains(transaction.kind) { return false }
            if !filter.accountIDs.isEmpty && !transaction.legs.contains(where: { filter.accountIDs.contains($0.accountID) }) {
                return false
            }
            if !categories.isEmpty && !(transaction.categoryID.map(categories.contains) ?? false) { return false }
            if !filter.tagIDs.isEmpty && (tags[transaction.id] ?? []).isDisjoint(with: filter.tagIDs) { return false }
            return search.map { $0.matches(transaction, snapshot: snapshot) } ?? true
        }
        .sorted { ($0.localDate, $0.occurredAt) > ($1.localDate, $1.occurredAt) }
    }

    /// Groups rows by day, newest day first, with the day's spending in base currency.
    public static func days(_ transactions: [MoneyTransaction], snapshot: LedgerSnapshot) -> [ActivityDay] {
        Dictionary(grouping: transactions, by: \.localDate)
            .map { date, rows in
                let totals = try? PeriodTotals.compute(rows, from: date, through: date, base: snapshot.base, rates: snapshot.rates)
                return ActivityDay(date: date, transactions: rows.sorted { $0.occurredAt > $1.occurredAt },
                                   spending: totals?.spending ?? .zero(snapshot.base))
            }
            .sorted { $0.date > $1.date }
    }

    /// The chosen IDs plus every child of a chosen parent.
    static func expandedCategories(_ ids: Set<UUID>, in categories: [SpendCategory]) -> Set<UUID> {
        guard !ids.isEmpty else { return [] }
        return ids.union(categories.filter { $0.parentID.map(ids.contains) ?? false }.map(\.id))
    }

    /// Search over payee, note, category and amount (TXN-025). Case- and accent-insensitive.
    struct SearchTerm {
        let key: String
        /// Set when the text reads as an amount ("8940", "8,940", "2.99").
        let amount: Decimal?

        init?(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            key = NameKey.make(trimmed)
            let digits = trimmed.replacingOccurrences(of: ",", with: "")
            amount = digits.allSatisfy({ $0.isASCIIDigit || $0 == "." }) && digits.contains(where: \.isASCIIDigit)
                ? Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX")) : nil
        }

        func matches(_ transaction: MoneyTransaction, snapshot: LedgerSnapshot) -> Bool {
            if let amount, transaction.amount.decimalValue == amount || transaction.myShare.decimalValue == amount
                || transaction.legs.contains(where: { $0.amount.decimalValue.magnitude == amount }) {
                return true
            }
            let fields = [transaction.payeeName, transaction.note, snapshot.categoryPath(transaction.categoryID)]
            return fields.contains { field in field.map { NameKey.make($0).contains(key) } ?? false }
        }
    }
}

/// The line under a row saying what the money did (TXN-021).
public enum ActivityText {
    public static func detail(_ transaction: MoneyTransaction) -> String? {
        if SpendingRules.isNeutral(transaction.kind) { return "not spending" }
        guard transaction.myShare != transaction.amount else { return nil }
        let share = MoneyFormatter.string(transaction.myShare, sign: .none)
        if transaction.legs.isEmpty { return "Someone else paid · your share \(share)" }
        let verb = SpendingRules.countsAsIncome(transaction.kind) ? "You received" : "You paid"
        return "\(verb) \(MoneyFormatter.string(transaction.amount, sign: .none)) · your share \(share)"
    }
}
