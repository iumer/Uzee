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
    public var recordRepayment: @Sendable (_ loan: UUID, _ amount: Money, _ account: UUID, _ date: Date) throws -> Void
    public var setWrittenOff: @Sendable (_ writtenOff: Bool, _ loan: UUID) throws -> Void
    public var setDueDate: @Sendable (_ due: LocalDate?, _ interestBasisPoints: Int?, _ loan: UUID) throws -> Void
    public var addExistingBalances: @Sendable ([BalanceRow]) throws -> Void
    public var settle: @Sendable (_ person: UUID, _ group: UUID?, _ amount: Money, _ iPaid: Bool, _ account: UUID, _ date: Date) throws -> Void

    public init(snapshot: @escaping @Sendable () throws -> PeopleSnapshot,
                createPerson: @escaping @Sendable (String, String?) throws -> Person,
                updatePerson: @escaping @Sendable (Person) throws -> Void,
                createGroup: @escaping @Sendable (String, GroupIcon, [UUID], SplitMethod) throws -> SplitGroup,
                updateGroup: @escaping @Sendable (SplitGroup) throws -> Void,
                saveSplit: @escaping @Sendable (MoneyTransaction, Split?) throws -> Void,
                recordLoan: @escaping @Sendable (LoanDirection, UUID, Money, UUID?, Date, LocalDate?, String?) throws -> Void,
                recordRepayment: @escaping @Sendable (UUID, Money, UUID, Date) throws -> Void,
                setWrittenOff: @escaping @Sendable (Bool, UUID) throws -> Void,
                setDueDate: @escaping @Sendable (LocalDate?, Int?, UUID) throws -> Void,
                addExistingBalances: @escaping @Sendable ([BalanceRow]) throws -> Void,
                settle: @escaping @Sendable (UUID, UUID?, Money, Bool, UUID, Date) throws -> Void) {
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
    }

    public static let unavailable = PeopleClient(
        snapshot: { .empty }, createPerson: { _, _ in throw CoreError.notFound }, updatePerson: { _ in throw CoreError.notFound },
        createGroup: { _, _, _, _ in throw CoreError.notFound }, updateGroup: { _ in throw CoreError.notFound },
        saveSplit: { _, _ in throw CoreError.notFound }, recordLoan: { _, _, _, _, _, _, _ in throw CoreError.notFound },
        recordRepayment: { _, _, _, _ in throw CoreError.notFound }, setWrittenOff: { _, _ in throw CoreError.notFound },
        setDueDate: { _, _, _ in throw CoreError.notFound }, addExistingBalances: { _ in throw CoreError.notFound },
        settle: { _, _, _, _, _, _ in throw CoreError.notFound })
}
