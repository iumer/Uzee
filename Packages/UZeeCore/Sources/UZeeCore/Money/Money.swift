import Foundation

/// An exact amount: Int64 minor units plus a currency. Never Double (DATA_MODEL §1).
/// Arithmetic arrives with the transaction engine in M2.
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

/// Converts between currencies with a rate meaning "base units per 1 foreign unit" (DATA_MODEL §1).
/// One rounding rule: half away from zero to the target's minor unit.
public enum CurrencyConverter {
    public static func convert(_ money: Money, to target: Currency, rate: Decimal) -> Money {
        if money.currency == target { return money }
        var value = Decimal(money.minorUnits) * rate
        let shift = target.minorUnits - money.currency.minorUnits
        if shift > 0 { value *= Decimal(Money.scale(shift)) }
        if shift < 0 { value /= Decimal(Money.scale(-shift)) }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return Money(minorUnits: NSDecimalNumber(decimal: rounded).int64Value, currency: target)
    }
}
