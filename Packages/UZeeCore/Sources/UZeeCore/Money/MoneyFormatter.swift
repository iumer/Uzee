import Foundation

/// The only place money becomes text (DESIGN_SYSTEM §4). Deterministic: no Locale,
/// so the same string appears on every device and in Linux tests.
public enum MoneyFormatter {
    public enum Sign: Sendable {
        /// Magnitude only (hero balance, cards).
        case none
        /// "−" for negative amounts only.
        case negativeOnly
        /// "+" for inflow and "−" for outflow (lists).
        case always
    }

    /// True minus sign (U+2212), never a hyphen.
    public static let minus = "\u{2212}"

    /// "Rs 182,400", "$520.00", "−Rs 1,600", "+$1,875.00".
    public static func string(_ money: Money, sign: Sign = .negativeOnly) -> String {
        let (whole, fraction) = displayParts(money)
        var number = grouped(whole)
        if money.currency.displayFractionDigits > 0 {
            number += "." + padded(fraction, to: money.currency.displayFractionDigits)
        }
        let symbol = money.currency.symbol + (money.currency.symbolNeedsSpace ? " " : "")
        let isZeroOnScreen = whole == 0 && fraction == 0
        let prefix: String
        switch sign {
        case .none: prefix = ""
        case .negativeOnly: prefix = money.isNegative && !isZeroOnScreen ? minus : ""
        case .always: prefix = isZeroOnScreen ? "" : (money.isNegative ? minus : "+")
        }
        return prefix + symbol + number
    }

    /// Second line under a foreign amount: "≈ Rs 145,600".
    public static func approximate(_ money: Money, in base: Currency, rate: Decimal) -> String {
        let converted = CurrencyConverter.convert(money, to: base, rate: rate)
        return "≈ " + string(converted, sign: .none)
    }

    /// Placeholder when amounts are hidden: "Rs •••••".
    public static func hidden(_ currency: Currency) -> String {
        currency.symbol + (currency.symbolNeedsSpace ? " " : "") + "•••••"
    }

    /// VoiceOver text: "182,400 rupees", "minus 1,600 rupees", "2 US dollars 99 cents".
    public static func spoken(_ money: Money) -> String {
        let (whole, fraction) = displayParts(money)
        let currency = money.currency
        var parts: [String] = []
        if whole != 0 || fraction == 0 {
            parts.append("\(grouped(whole)) \(whole == 1 ? currency.spokenSingular : currency.spokenPlural)")
        }
        if fraction != 0 {
            parts.append("\(fraction) \(fraction == 1 ? currency.spokenMinorSingular : currency.spokenMinorPlural)")
        }
        let text = parts.joined(separator: " ")
        return money.isNegative && (whole != 0 || fraction != 0) ? "minus " + text : text
    }

    /// Spoken foreign amount with its base equivalent: "20 US dollars, about 5,600 rupees".
    public static func spoken(_ money: Money, base: Currency, rate: Decimal) -> String {
        guard money.currency != base else { return spoken(money) }
        let converted = CurrencyConverter.convert(money, to: base, rate: rate)
        return spoken(money) + ", about " + spoken(Money(minorUnits: abs(converted.minorUnits), currency: base))
    }

    /// Magnitude split into whole units and shown decimals, rounded half up for display only.
    static func displayParts(_ money: Money) -> (whole: UInt64, fraction: UInt64) {
        let currency = money.currency
        let magnitude = money.minorUnits.magnitude
        let dropped = currency.minorUnits - currency.displayFractionDigits
        let divisor = UInt64(Money.scale(dropped))
        // Display rounding goes through the single rounding function too (CUR-005).
        let shown = dropped == 0 ? magnitude
            : UInt64(Rounding.halfUp(Decimal(magnitude) / Decimal(divisor), scale: 0).description) ?? magnitude / divisor
        let fractionScale = UInt64(Money.scale(currency.displayFractionDigits))
        return (shown / fractionScale, shown % fractionScale)
    }

    /// 1234567 → "1,234,567" (international grouping, DESIGN_SYSTEM §4).
    static func grouped(_ value: UInt64) -> String {
        let digits = Array(String(value))
        var out = ""
        for (index, digit) in digits.enumerated() {
            if index > 0 && (digits.count - index) % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return out
    }

    static func padded(_ value: UInt64, to width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}
