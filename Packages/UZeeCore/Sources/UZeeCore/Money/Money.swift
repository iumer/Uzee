import Foundation

/// An exact amount: Int64 minor units plus a currency. Never Double (DATA_MODEL §1).
/// Arithmetic is allowed only between equal currencies and is overflow-checked (DATA_MODEL §4).
public struct Money: Hashable, Sendable {
    public let minorUnits: Int64
    public let currency: Currency

    public init(minorUnits: Int64, currency: Currency) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    /// Whole major units, e.g. `Money(major: 182_400, .pkr)` = Rs 182,400.
    public init(major: Int64, _ currency: Currency) {
        self.init(minorUnits: major * Self.scale(currency.minorUnits), currency: currency)
    }

    public var isNegative: Bool { minorUnits < 0 }
    public var isZero: Bool { minorUnits == 0 }

    static func scale(_ digits: Int) -> Int64 {
        var value: Int64 = 1
        for _ in 0..<digits { value *= 10 }
        return value
    }
}

/// Why a money operation was refused. Shown to the user as "Amount too large" etc. by the UI layer.
public enum MoneyError: Error, Equatable, Sendable {
    case currencyMismatch
    case overflow
}

extension Money {
    /// Zero in the given currency.
    public static func zero(_ currency: Currency) -> Money { Money(minorUnits: 0, currency: currency) }

    public func adding(_ other: Money) throws(MoneyError) -> Money {
        guard currency == other.currency else { throw .currencyMismatch }
        let (value, overflow) = minorUnits.addingReportingOverflow(other.minorUnits)
        guard !overflow else { throw .overflow }
        return Money(minorUnits: value, currency: currency)
    }

    public func subtracting(_ other: Money) throws(MoneyError) -> Money {
        guard currency == other.currency else { throw .currencyMismatch }
        let (value, overflow) = minorUnits.subtractingReportingOverflow(other.minorUnits)
        guard !overflow else { throw .overflow }
        return Money(minorUnits: value, currency: currency)
    }

    public func negated() throws(MoneyError) -> Money {
        guard minorUnits != .min else { throw .overflow }
        return Money(minorUnits: -minorUnits, currency: currency)
    }

    public func multiplied(by factor: Int64) throws(MoneyError) -> Money {
        let (value, overflow) = minorUnits.multipliedReportingOverflow(by: factor)
        guard !overflow else { throw .overflow }
        return Money(minorUnits: value, currency: currency)
    }

    /// Absolute value (amounts on rows are shown unsigned with a separate sign).
    public func magnitude() throws(MoneyError) -> Money {
        minorUnits < 0 ? try negated() : self
    }

    /// Sum of amounts that must all be in `currency`; an empty list is zero.
    public static func sum(_ amounts: some Sequence<Money>, in currency: Currency) throws(MoneyError) -> Money {
        var total = Money.zero(currency)
        for amount in amounts { total = try total.adding(amount) }
        return total
    }

    /// Comparison only within one currency (CUR-003: never compare Rs with $).
    public func compare(_ other: Money) throws(MoneyError) -> ComparisonResult {
        guard currency == other.currency else { throw .currencyMismatch }
        if minorUnits == other.minorUnits { return .orderedSame }
        return minorUnits < other.minorUnits ? .orderedAscending : .orderedDescending
    }

    /// Exact value in major units, e.g. 837.20 for Rs 837.20.
    public var decimalValue: Decimal {
        Decimal(minorUnits) / Decimal(Money.scale(currency.minorUnits))
    }

    /// Exact major-unit value to minor units, half-up via `Rounding` (used by conversions only).
    public static func fromMajor(_ value: Decimal, _ currency: Currency) throws(MoneyError) -> Money {
        let minor = Rounding.halfUp(value * Decimal(Money.scale(currency.minorUnits)), scale: 0)
        guard let units = Rounding.int64(minor) else { throw .overflow }
        return Money(minorUnits: units, currency: currency)
    }
}

/// Converts between currencies with a rate meaning "base units per 1 foreign unit" (DATA_MODEL §1).
/// Rounds once, half-up to the target's minor unit, through `Rounding`.
public enum CurrencyConverter {
    /// Converts `money` into `target`. `rate` is target units per 1 unit of `money.currency`.
    public static func convert(_ money: Money, to target: Currency, rate: Decimal) -> Money {
        (try? convertChecked(money, to: target, rate: rate)) ?? Money(minorUnits: money.minorUnits < 0 ? .min : .max, currency: target)
    }

    public static func convertChecked(_ money: Money, to target: Currency, rate: Decimal) throws(MoneyError) -> Money {
        if money.currency == target { return money }
        return try Money.fromMajor(money.decimalValue * rate, target)
    }
}
