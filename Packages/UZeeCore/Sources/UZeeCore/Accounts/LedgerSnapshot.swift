import Foundation

/// Everything the M2 screens show at once: accounts with derived balances and the available total.
public struct LedgerSnapshot: Sendable, Equatable {
    public var base: Currency
    public var accounts: [Account]
    public var balances: [UUID: Money]
    public var available: Money
    /// "USD at $1 = Rs 280" when the total converted something (AUD-04).
    public var footnote: String?
    public var rates: [String: Decimal]
    public var categories: [SpendCategory]

    public init(base: Currency, accounts: [Account], balances: [UUID: Money], available: Money, footnote: String?,
                rates: [String: Decimal], categories: [SpendCategory]) {
        self.base = base
        self.accounts = accounts
        self.balances = balances
        self.available = available
        self.footnote = footnote
        self.rates = rates
        self.categories = categories
    }

    public static func empty(base: Currency = .pkr) -> LedgerSnapshot {
        LedgerSnapshot(base: base, accounts: [], balances: [:], available: .zero(base), footnote: nil,
                       rates: ["USD": ExchangeRate.defaultUSD.rate], categories: [])
    }

    public func balance(of account: Account) -> Money { balances[account.id] ?? account.openingBalance }

    /// Table rate for showing `currency` in base ("≈ Rs"), 1 for the base itself.
    public func rate(for currency: Currency) -> Decimal {
        currency == base ? 1 : rates[currency.code] ?? ExchangeRate.defaultUSD.rate
    }

    public func account(_ id: UUID?) -> Account? { accounts.first { $0.id == id } }

    /// Non-archived accounts, for pickers (ACC-005).
    public var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    public func category(_ id: UUID?) -> SpendCategory? { categories.first { $0.id == id } }

    /// "Transport › Fuel"; income items read "Income › Salary".
    public func categoryPath(_ id: UUID?) -> String? {
        guard let category = category(id) else { return nil }
        if let parent = self.category(category.parentID) { return "\(parent.name) › \(category.name)" }
        return category.type == .income ? "Income › \(category.name)" : category.name
    }
}
