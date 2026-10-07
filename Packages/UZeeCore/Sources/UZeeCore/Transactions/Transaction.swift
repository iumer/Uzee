import Foundation

/// Which side of a transaction a leg is (DATA_MODEL §3.7).
public enum LegRole: String, CaseIterable, Sendable, Codable {
    case main, transferOut, transferIn
}

/// One account movement. Negative = money leaves the account.
public struct TransactionLeg: Hashable, Sendable {
    public var accountID: UUID
    public var amount: Money
    public var role: LegRole

    public init(accountID: UUID, amount: Money, role: LegRole) {
        self.accountID = accountID
        self.amount = amount
        self.role = role
    }
}

/// A saved transaction with its legs (DATA_MODEL §3.6).
public struct Transaction: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: TransactionKind
    public var status: TransactionStatus
    public var occurredAt: Date
    public var localDate: LocalDate
    public var timeZoneID: String
    /// Gross amount, always positive. For a transfer, the amount sent.
    public var amount: Money
    /// Spending/income counts my share only (filled by splits in M5; equals `amount` until then).
    public var myShare: Money
    public var categoryID: UUID?
    public var payeeName: String?
    public var note: String?
    /// Real rate of a cross-currency transfer, base units per foreign unit (TXN-03).
    public var fxRate: Decimal?
    public var source: EntrySource
    public var legs: [TransactionLeg]
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var isSample: Bool

    public init(id: UUID = UUID(), kind: TransactionKind, status: TransactionStatus = .posted,
                occurredAt: Date, localDate: LocalDate, timeZoneID: String, amount: Money, myShare: Money? = nil,
                categoryID: UUID? = nil, payeeName: String? = nil, note: String? = nil, fxRate: Decimal? = nil,
                source: EntrySource = .manual, legs: [TransactionLeg],
                createdAt: Date = Date(), updatedAt: Date? = nil, deletedAt: Date? = nil, isSample: Bool = false) {
        self.id = id
        self.kind = kind
        self.status = status
        self.occurredAt = occurredAt
        self.localDate = localDate
        self.timeZoneID = timeZoneID
        self.amount = amount
        self.myShare = myShare ?? amount
        self.categoryID = categoryID
        self.payeeName = payeeName
        self.note = note
        self.fxRate = fxRate
        self.source = source
        self.legs = legs
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
        self.isSample = isSample
    }

    /// Counts in balances and totals: posted and not deleted.
    public var isEffective: Bool { status == .posted && deletedAt == nil }
}
