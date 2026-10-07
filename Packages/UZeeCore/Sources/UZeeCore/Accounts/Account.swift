import Foundation

/// Account types (ACC-02). Raw values are stored; unknown values from a newer app decode to `.other`.
public enum AccountKind: String, CaseIterable, Sendable, Codable {
    case cash, bank, savings, creditCard, wallet, multiCurrency, cryptoFiat, other

    public var name: String {
        switch self {
        case .cash: "Cash"
        case .bank: "Bank"
        case .savings: "Savings"
        case .creditCard: "Credit card"
        case .wallet: "Wallet"
        case .multiCurrency: "Multi-currency"
        case .cryptoFiat: "Crypto card"
        case .other: "Other"
        }
    }

    /// Generic SF Symbols only, never bank logos (AUD-42).
    public var symbolName: String {
        switch self {
        case .cash: "banknote"
        case .bank: "building.columns"
        case .savings: "lock.shield"
        case .creditCard: "creditcard"
        case .wallet: "wallet.bifold"
        case .multiCurrency: "globe"
        case .cryptoFiat: "creditcard.and.123"
        case .other: "tray"
        }
    }
}

/// A place money lives (DATA_MODEL §3.5). Its balance is never stored; see `BalanceCalculator`.
public struct Account: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: AccountKind
    public var currency: Currency
    public var openingBalance: Money
    public var openingDate: LocalDate
    public var includeInTotals: Bool
    public var colorHex: String
    public var sortOrder: Int
    public var archivedAt: Date?
    public var isSample: Bool

    public init(id: UUID = UUID(), name: String, kind: AccountKind, currency: Currency,
                openingBalance: Money? = nil, openingDate: LocalDate, includeInTotals: Bool = true,
                colorHex: String = "#007AFF", sortOrder: Int = 0, archivedAt: Date? = nil, isSample: Bool = false) {
        self.id = id
        self.name = name
        self.kind = kind
        self.currency = currency
        self.openingBalance = openingBalance ?? .zero(currency)
        self.openingDate = openingDate
        self.includeInTotals = includeInTotals
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.archivedAt = archivedAt
        self.isSample = isSample
    }

    public var isArchived: Bool { archivedAt != nil }

    /// Why an account form cannot be saved (ACC-008).
    public enum Problem: Error, Equatable, Sendable {
        case emptyName
        case nameTooLong
        case duplicateName
        case currencyLocked
    }

    public static let maxNameLength = 40

    /// Checks the name against the other accounts' names (case- and space-insensitive).
    public static func validateName(_ name: String, existingNames: [String]) throws(Problem) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .emptyName }
        guard trimmed.count <= maxNameLength else { throw .nameTooLong }
        let key = NameKey.make(trimmed)
        guard !existingNames.contains(where: { NameKey.make($0) == key }) else { throw .duplicateName }
        return trimmed
    }
}

/// `*_key` normalisation (DATA_MODEL §1): lowercased, trimmed, diacritics folded, inner spaces collapsed.
public enum NameKey {
    public static func make(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
