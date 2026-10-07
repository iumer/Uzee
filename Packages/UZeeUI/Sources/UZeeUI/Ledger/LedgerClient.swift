import Foundation
import UZeeCore

/// The ledger operations the screens need, injected by the app so UZeeUI never imports the
/// database package (ARCHITECTURE layers). Every call is synchronous and fast (local SQLite).
public struct LedgerClient: Sendable {
    public struct NewAccount: Sendable, Equatable {
        public var name: String
        public var kind: AccountKind
        public var currency: Currency
        public var openingBalance: Money
        public var openingDate: LocalDate
        public var includeInTotals: Bool

        public init(name: String, kind: AccountKind, currency: Currency, openingBalance: Money,
                    openingDate: LocalDate, includeInTotals: Bool) {
            self.name = name
            self.kind = kind
            self.currency = currency
            self.openingBalance = openingBalance
            self.openingDate = openingDate
            self.includeInTotals = includeInTotals
        }
    }

    public var snapshot: @Sendable () throws -> LedgerSnapshot
    public var transactions: @Sendable () throws -> [Transaction]
    public var lastUsedAccountID: @Sendable () throws -> UUID?
    public var save: @Sendable (Transaction) throws -> Void
    public var delete: @Sendable (UUID) throws -> Void
    /// Undo right after saving: removes the row for good (TXN-013).
    public var discard: @Sendable (UUID) throws -> Void
    public var createAccount: @Sendable (NewAccount) throws -> Account
    public var updateAccount: @Sendable (Account) throws -> Void
    public var setArchived: @Sendable (Bool, UUID) throws -> Void
    public var deleteAccount: @Sendable (UUID) throws -> Void
    public var hasTransactions: @Sendable (UUID) throws -> Bool
    public var setRate: @Sendable (Decimal, Currency) throws -> Void

    public init(snapshot: @escaping @Sendable () throws -> LedgerSnapshot,
                transactions: @escaping @Sendable () throws -> [Transaction],
                lastUsedAccountID: @escaping @Sendable () throws -> UUID?,
                save: @escaping @Sendable (Transaction) throws -> Void,
                delete: @escaping @Sendable (UUID) throws -> Void,
                discard: @escaping @Sendable (UUID) throws -> Void,
                createAccount: @escaping @Sendable (NewAccount) throws -> Account,
                updateAccount: @escaping @Sendable (Account) throws -> Void,
                setArchived: @escaping @Sendable (Bool, UUID) throws -> Void,
                deleteAccount: @escaping @Sendable (UUID) throws -> Void,
                hasTransactions: @escaping @Sendable (UUID) throws -> Bool,
                setRate: @escaping @Sendable (Decimal, Currency) throws -> Void) {
        self.snapshot = snapshot
        self.transactions = transactions
        self.lastUsedAccountID = lastUsedAccountID
        self.save = save
        self.delete = delete
        self.discard = discard
        self.createAccount = createAccount
        self.updateAccount = updateAccount
        self.setArchived = setArchived
        self.deleteAccount = deleteAccount
        self.hasTransactions = hasTransactions
        self.setRate = setRate
    }

    /// No database: empty and read-only.
    public static let unavailable = LedgerClient(
        snapshot: { .empty() }, transactions: { [] }, lastUsedAccountID: { nil },
        save: { _ in throw CoreError.notFound }, delete: { _ in throw CoreError.notFound }, discard: { _ in },
        createAccount: { _ in throw CoreError.notFound }, updateAccount: { _ in throw CoreError.notFound },
        setArchived: { _, _ in throw CoreError.notFound }, deleteAccount: { _ in throw CoreError.notFound },
        hasTransactions: { _ in false }, setRate: { _, _ in throw CoreError.notFound })
}
