import Foundation

/// A table rate: `rate` base-currency units per 1 unit of `currency` (DATA_MODEL §3.4).
public struct ExchangeRate: Hashable, Sendable {
    public let currency: Currency
    public let base: Currency
    public let rate: Decimal

    public init(currency: Currency, base: Currency, rate: Decimal) {
        self.currency = currency
        self.base = base
        self.rate = rate
    }

    /// The v1 default, $1 = Rs 280 (CUR-03).
    public static let defaultUSD = ExchangeRate(currency: .usd, base: .pkr, rate: 280)

    public enum Failure: Error, Equatable, Sendable {
        case empty
        case notANumber
        case notPositive
    }

    /// Parses a typed rate exactly (CUR-012): "280", "278.705". Zero, negative, empty and text are refused.
    public static func parseRate(_ text: String) throws(Failure) -> Decimal {
        let cleaned = text.filter { !$0.isWhitespace && $0 != "," }
        guard !cleaned.isEmpty else { throw .empty }
        if cleaned.hasPrefix("-") || cleaned.hasPrefix("\u{2212}") { throw .notPositive }
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
              !parts[0].isEmpty || (parts.count == 2 && !parts[1].isEmpty),
              cleaned.count <= 20,
              let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { throw .notANumber }
        guard value > 0 else { throw .notPositive }
        return value
    }

    /// "280.00", "278.70", "278.705": at least two decimals, never rounded away.
    public static func display(_ rate: Decimal) -> String {
        var text = rate.description
        if !text.contains(".") { text += "." }
        let decimals = text.split(separator: ".", omittingEmptySubsequences: false).last?.count ?? 0
        if decimals < 2 { text += String(repeating: "0", count: 2 - decimals) }
        return text
    }

    /// Canonical text stored in SQLite (DATA_MODEL §1 "Rates").
    public static func storageString(_ rate: Decimal) -> String { rate.description }

    public static func fromStorage(_ text: String) -> Decimal? {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// The real rate of a cross-currency transfer and how it compares with the table rate (TXN-03, CUR-009).
public struct TransferRate: Equatable, Sendable {
    /// Base units per 1 foreign unit, from the two legs, kept to 6 decimals.
    public let rate: Decimal
    /// Received minus what the table rate would have given, in base currency. Negative = got less.
    public let differenceFromTable: Money

    /// `foreign` is the amount in the non-base currency, `base` the amount in the base currency.
    public init(foreign: Money, base: Money, tableRate: Decimal) throws(MoneyError) {
        guard foreign.minorUnits != 0 else { throw .overflow }
        rate = Rounding.halfUp(base.decimalValue / foreign.decimalValue, scale: 6)
        let atTable = try CurrencyConverter.convertChecked(foreign, to: base.currency, rate: tableRate)
        differenceFromTable = try base.subtracting(atTable)
    }
}
