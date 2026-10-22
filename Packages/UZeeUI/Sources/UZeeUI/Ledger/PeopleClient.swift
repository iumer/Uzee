import Foundation
import UZeeCore

/// M5 people, loan, split and settle-up operations, injected like `LedgerClient`.
public struct PeopleClient: Sendable {
    public typealias BalanceRow = (name: String, direction: LoanDirection, amount: Money)

    public var snapshot: @Sendable () throws -> PeopleSnapshot
    public var createPerson: @Sendable (_ name: String, _ phone: String?) throws -> Person
    public var updatePerson: @Sendable (Person) throws -> Void
    public var createGroup: @Sendable (_ name: String, _ icon: GroupIcon, _ members: [UUID], _ method: SplitMethod) throws -> SplitGroup
    public var updateGroup: @Sendable (SplitGroup) throws -> Void
    /// Saves a transaction with its split (nil removes the split).
    public var saveSplit: @Sendable (MoneyTransaction, Split?) throws -> Void
    public var recordLoan: @Sendable (_ direction: LoanDirection, _ person: UUID, _ amount: Money, _ account: UUID?, _ date: Date,
                                      _ due: LocalDate?, _ note: String?) throws -> Void
    public var recordRepayment: @Sendable (_ loan: UUID, _ amount: Money, _ account: UUID?, _ date: Date) throws -> Void
    /// A repayment into or out of an account in another currency: `received` is what actually moved there.
    public var recordRepaymentReceived: @Sendable (_ loan: UUID, _ amount: Money, _ account: UUID, _ date: Date, _ received: Money) throws -> Void
    public var setWrittenOff: @Sendable (_ writtenOff: Bool, _ loan: UUID) throws -> Void
    public var setDueDate: @Sendable (_ due: LocalDate?, _ interestBasisPoints: Int?, _ loan: UUID) throws -> Void
    public var addExistingBalances: @Sendable ([BalanceRow]) throws -> Void
    public var settle: @Sendable (_ person: UUID, _ group: UUID?, _ amount: Money, _ iPaid: Bool, _ account: UUID, _ date: Date) throws -> Void
    /// Dated notes on a loan, like a chat (owner, 2026-10-15).
    public var addLoanNote: @Sendable (_ text: String, _ loan: UUID) throws -> Void
    public var deleteLoanNote: @Sendable (_ note: UUID) throws -> Void
    /// The same notes on a shared expense or any entry with a person (owner, 2026-10-19).
    public var entryNotes: @Sendable (_ transaction: UUID) throws -> [LoanNote]
    public var addEntryNote: @Sendable (_ text: String, _ transaction: UUID) throws -> Void
    public var deleteEntryNote: @Sendable (_ note: UUID) throws -> Void
    /// Edit a loan's amount, date, account and note (owner, 2026-10-19).
    public var updateLoan: @Sendable (_ loan: UUID, _ amount: Money, _ date: Date, _ account: UUID?, _ note: String?) throws -> Void
    /// Delete and undo for records kept without a transaction, and for people (owner, 2026-10-19).
    public var deleteLoanRecord: @Sendable (_ loan: UUID) throws -> Void
    public var restoreLoanRecord: @Sendable (_ loan: UUID) throws -> Void
    public var deleteLoanPayment: @Sendable (_ payment: UUID) throws -> Void
    public var restoreLoanPayment: @Sendable (_ payment: UUID) throws -> Void
    public var deletePerson: @Sendable (_ person: UUID) throws -> Void
    public var restorePerson: @Sendable (_ person: UUID) throws -> Void

    public init(snapshot: @escaping @Sendable () throws -> PeopleSnapshot,
                createPerson: @escaping @Sendable (String, String?) throws -> Person,
                updatePerson: @escaping @Sendable (Person) throws -> Void,
                createGroup: @escaping @Sendable (String, GroupIcon, [UUID], SplitMethod) throws -> SplitGroup,
                updateGroup: @escaping @Sendable (SplitGroup) throws -> Void,
                saveSplit: @escaping @Sendable (MoneyTransaction, Split?) throws -> Void,
                recordLoan: @escaping @Sendable (LoanDirection, UUID, Money, UUID?, Date, LocalDate?, String?) throws -> Void,
                recordRepayment: @escaping @Sendable (UUID, Money, UUID?, Date) throws -> Void,
                setWrittenOff: @escaping @Sendable (Bool, UUID) throws -> Void,
                setDueDate: @escaping @Sendable (LocalDate?, Int?, UUID) throws -> Void,
                addExistingBalances: @escaping @Sendable ([BalanceRow]) throws -> Void,
                settle: @escaping @Sendable (UUID, UUID?, Money, Bool, UUID, Date) throws -> Void,
                addLoanNote: @escaping @Sendable (String, UUID) throws -> Void = { _, _ in throw CoreError.notFound },
                deleteLoanNote: @escaping @Sendable (UUID) throws -> Void = { _ in throw CoreError.notFound },
                entryNotes: @escaping @Sendable (UUID) throws -> [LoanNote] = { _ in [] },
                addEntryNote: @escaping @Sendable (String, UUID) throws -> Void = { _, _ in throw CoreError.notFound },
                deleteEntryNote: @escaping @Sendable (UUID) throws -> Void = { _ in throw CoreError.notFound },
                updateLoan: @escaping @Sendable (UUID, Money, Date, UUID?, String?) throws -> Void = { _, _, _, _, _ in throw CoreError.notFound },
                deleteLoanRecord: @escaping @Sendable (UUID) throws -> Void = { _ in throw CoreError.notFound },
                restoreLoanRecord: @escaping @Sendable (UUID) throws -> Void = { _ in throw CoreError.notFound },
                deleteLoanPayment: @escaping @Sendable (UUID) throws -> Void = { _ in throw CoreError.notFound },
                restoreLoanPayment: @escaping @Sendable (UUID) throws -> Void = { _ in throw CoreError.notFound },
                deletePerson: @escaping @Sendable (UUID) throws -> Void = { _ in throw CoreError.notFound },
                recordRepaymentReceived: @escaping @Sendable (UUID, Money, UUID, Date, Money) throws -> Void = { _, _, _, _, _ in
                    throw CoreError.notFound
                },
                restorePerson: @escaping @Sendable (UUID) throws -> Void = { _ in throw CoreError.notFound }) {
        self.snapshot = snapshot
        self.createPerson = createPerson
        self.updatePerson = updatePerson
        self.createGroup = createGroup
        self.updateGroup = updateGroup
        self.saveSplit = saveSplit
        self.recordLoan = recordLoan
        self.recordRepayment = recordRepayment
        self.setWrittenOff = setWrittenOff
        self.setDueDate = setDueDate
        self.addExistingBalances = addExistingBalances
        self.settle = settle
        self.addLoanNote = addLoanNote
        self.deleteLoanNote = deleteLoanNote
        self.entryNotes = entryNotes
        self.addEntryNote = addEntryNote
        self.deleteEntryNote = deleteEntryNote
        self.updateLoan = updateLoan
        self.deleteLoanRecord = deleteLoanRecord
        self.restoreLoanRecord = restoreLoanRecord
        self.deleteLoanPayment = deleteLoanPayment
        self.restoreLoanPayment = restoreLoanPayment
        self.deletePerson = deletePerson
        self.recordRepaymentReceived = recordRepaymentReceived
        self.restorePerson = restorePerson
    }

    public static let unavailable = PeopleClient(
        snapshot: { .empty }, createPerson: { _, _ in throw CoreError.notFound }, updatePerson: { _ in throw CoreError.notFound },
        createGroup: { _, _, _, _ in throw CoreError.notFound }, updateGroup: { _ in throw CoreError.notFound },
        saveSplit: { _, _ in throw CoreError.notFound }, recordLoan: { _, _, _, _, _, _, _ in throw CoreError.notFound },
        recordRepayment: { _, _, _, _ in throw CoreError.notFound }, setWrittenOff: { _, _ in throw CoreError.notFound },
        setDueDate: { _, _, _ in throw CoreError.notFound }, addExistingBalances: { _ in throw CoreError.notFound },
        settle: { _, _, _, _, _, _ in throw CoreError.notFound })
}
