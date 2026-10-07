import Foundation

/// The only place UZee rounds money or rates (DATA_MODEL §4, CUR-005).
/// Half-up means halves go away from zero: 2.785 → 2.79, −2.785 → −2.79.
public enum Rounding {
    public static func halfUp(_ value: Decimal, scale: Int) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }

    /// A whole Decimal as Int64, or nil when it does not fit (or is not whole).
    static func int64(_ value: Decimal) -> Int64? {
        guard value == halfUp(value, scale: 0),
              value <= Decimal(Int64.max), value >= Decimal(Int64.min) else { return nil }
        // Through the canonical string, so no binary floating point is involved on any platform.
        return Int64(value.description)
    }
}
