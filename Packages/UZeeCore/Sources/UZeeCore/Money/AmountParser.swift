import Foundation

/// Turns typed text into exact money (DATA_MODEL §4 "Input"): no silent rounding, no floating point.
public enum AmountParser {
    public enum Failure: Error, Equatable, Sendable {
        case empty
        case notANumber
        case tooManyDecimals(allowed: Int)
        /// More than `maxIntegerDigits` digits before the decimal point (SMK-012, TXN-009).
        case tooLarge
        case negative
    }

    /// 12 integer digits = up to Rs 999,999,999,999; a 13th digit is refused.
    public static let maxIntegerDigits = 12

    /// Accepts "1500", "1,500", "1 500.50", "2.99". Grouping commas and spaces are ignored.
    public static func parse(_ text: String, currency: Currency) throws(Failure) -> Money {
        let cleaned = text.filter { !$0.isWhitespace && $0 != "," }
        guard !cleaned.isEmpty else { throw .empty }
        if cleaned.hasPrefix("-") || cleaned.hasPrefix("\u{2212}") { throw .negative }
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let whole = parts.first,
              !(whole.isEmpty && (parts.count == 1 || parts[1].isEmpty)),
              whole.allSatisfy(\.isASCIIDigit) else { throw .notANumber }
        let fraction = parts.count == 2 ? parts[1] : ""
        guard fraction.allSatisfy(\.isASCIIDigit) else { throw .notANumber }
        guard fraction.count <= currency.minorUnits else { throw .tooManyDecimals(allowed: currency.minorUnits) }
        let significant = whole.drop { $0 == "0" }
        guard significant.count <= maxIntegerDigits else { throw .tooLarge }
        let padded = String(fraction) + String(repeating: "0", count: currency.minorUnits - fraction.count)
        // At most 12 + 3 digits, so this always fits in Int64.
        let minor = Int64(String(significant) + padded) ?? 0
        return Money(minorUnits: minor, currency: currency)
    }
}

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
