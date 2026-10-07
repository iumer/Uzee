import Foundation

/// Lent (they owe me) or borrowed (I owe them) (LOAN-02). Raw values are stored.
public enum LoanDirection: String, CaseIterable, Sendable, Codable {
    case lent, borrowed
}

/// Derived, never stored (DATA_MODEL §3.16).
public enum LoanStatus: String, Sendable {
    case open, partiallyPaid, settled, writtenOff

    public var name: String {
        switch self {
        case .open: "Open"
        case .partiallyPaid: "Partially paid"
        case .settled: "Settled"
        case .writtenOff: "Written off"
        }
    }
}

public struct LoanPayment: Hashable, Sendable, Identifiable {
    public var id: UUID
    /// The repayment transaction; nil only for payments made before tracking (opening balances).
    public var transactionID: UUID?
    public var amount: Money
    public var paidOn: LocalDate

    public init(id: UUID = UUID(), transactionID: UUID? = nil, amount: Money, paidOn: LocalDate) {
        self.id = id
        self.transactionID = transactionID
        self.amount = amount
        self.paidOn = paidOn
    }
}

/// A loan with a person or an institution (LOAN-02). `transactionID` is the lend/borrow transaction
/// that moved the money (LOAN-05); nil for an opening balance (LOAN-08).
public struct Loan: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var direction: LoanDirection
    public var personID: UUID?
    public var institution: String?
    public var principal: Money
    public var startDate: LocalDate
    public var dueDate: LocalDate?
    /// Simple yearly rate in basis points; display only in v1.
    public var interestBasisPoints: Int?
    public var transactionID: UUID?
    public var writtenOffAt: Date?
    public var notes: String?
    public var payments: [LoanPayment]
    public var isSample: Bool

    public init(id: UUID = UUID(), direction: LoanDirection, personID: UUID? = nil, institution: String? = nil, principal: Money,
                startDate: LocalDate, dueDate: LocalDate? = nil, interestBasisPoints: Int? = nil, transactionID: UUID? = nil,
                writtenOffAt: Date? = nil, notes: String? = nil, payments: [LoanPayment] = [], isSample: Bool = false) {
        self.id = id
        self.direction = direction
        self.personID = personID
        self.institution = institution
        self.principal = principal
        self.startDate = startDate
        self.dueDate = dueDate
        self.interestBasisPoints = interestBasisPoints
        self.transactionID = transactionID
        self.writtenOffAt = writtenOffAt
        self.notes = notes
        self.payments = payments
        self.isSample = isSample
    }

    public var isOpeningBalance: Bool { transactionID == nil }
}

/// Loan arithmetic (LOAN-03, DATA_MODEL §4 "Interest").
public enum LoanCalculator {
    public enum Problem: Error, Equatable, Sendable {
        case invalidAmount
        /// A repayment bigger than what is left.
        case moreThanOutstanding(outstanding: Money)
        case writtenOff
    }

    public static func paid(_ loan: Loan) -> Money {
        Money(minorUnits: loan.payments.reduce(Int64(0)) { $0 &+ $1.amount.minorUnits }, currency: loan.principal.currency)
    }

    /// Principal − payments, never below zero; zero once written off.
    public static func outstanding(_ loan: Loan) -> Money {
        guard loan.writtenOffAt == nil else { return .zero(loan.principal.currency) }
        return Money(minorUnits: max(0, loan.principal.minorUnits - paid(loan).minorUnits), currency: loan.principal.currency)
    }

    public static func status(_ loan: Loan) -> LoanStatus {
        if loan.writtenOffAt != nil { return .writtenOff }
        if outstanding(loan).isZero { return .settled }
        return loan.payments.isEmpty ? .open : .partiallyPaid
    }

    /// Checks a repayment before it is saved.
    public static func validatePayment(_ amount: Money, for loan: Loan) throws(Problem) {
        guard loan.writtenOffAt == nil else { throw .writtenOff }
        guard amount.minorUnits > 0, amount.currency == loan.principal.currency else { throw .invalidAmount }
        let left = outstanding(loan)
        guard amount.minorUnits <= left.minorUnits else { throw .moreThanOutstanding(outstanding: left) }
    }

    /// Simple interest on the principal from the start date to `date`: principal × rate × days / 365, half-up.
    public static func interest(_ loan: Loan, asOf date: LocalDate) -> Money {
        guard let bps = loan.interestBasisPoints, bps > 0 else { return .zero(loan.principal.currency) }
        let days = max(0, loan.startDate.days(to: date))
        let value = loan.principal.decimalValue * Decimal(bps) / 10_000 * Decimal(days) / 365
        return (try? Money.fromMajor(value, loan.principal.currency)) ?? .zero(loan.principal.currency)
    }

    /// Signed outstanding from my side: + they owe me (lent), − I owe them (borrowed).
    public static func signedOutstanding(_ loan: Loan) -> Money {
        let left = outstanding(loan)
        return loan.direction == .lent ? left : Money(minorUnits: -left.minorUnits, currency: left.currency)
    }
}
