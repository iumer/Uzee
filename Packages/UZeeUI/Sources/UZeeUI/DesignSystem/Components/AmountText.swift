import SwiftUI
import UZeeCore

/// Renders money with every DESIGN_SYSTEM §4 rule: symbol, true minus, tabular digits,
/// "≈ Rs" line for foreign amounts, hidden mode and a spoken VoiceOver label.
public struct AmountText: View {
    public enum Style: Sendable {
        /// No sign (hero balance, cards).
        case plain
        /// Expense in lists: label colour with "−".
        case outflow
        /// Income: "+" in positive green.
        case inflow
        /// Transfers: secondary colour.
        case transfer
    }

    let money: Money
    let style: Style
    let font: Font
    let base: Currency
    let rate: Decimal
    @Environment(\.redactionReasons) private var redaction
    @Environment(\.uzHideAmounts) private var hideAmounts

    public init(_ money: Money, style: Style = .plain, font: Font = .body.weight(.semibold),
                base: Currency = .pkr, rate: Decimal = 280) {
        self.money = money
        self.style = style
        self.font = font
        self.base = base
        self.rate = rate
    }

    var isHidden: Bool { hideAmounts || redaction.contains(.privacy) }

    var primaryText: String {
        if isHidden { return MoneyFormatter.hidden(money.currency) }
        switch style {
        case .plain: return MoneyFormatter.string(money, sign: .none)
        case .outflow: return MoneyFormatter.string(Money(minorUnits: -money.minorUnits.magnitudeClamped, currency: money.currency))
        case .inflow: return MoneyFormatter.string(Money(minorUnits: money.minorUnits.magnitudeClamped, currency: money.currency), sign: .always)
        case .transfer: return MoneyFormatter.string(money)
        }
    }

    var secondaryText: String? {
        guard money.currency != base, !isHidden else { return nil }
        return MoneyFormatter.approximate(money, in: base, rate: rate)
    }

    var spokenText: String {
        if isHidden { return "amount hidden" }
        var value = money
        if style == .outflow { value = Money(minorUnits: -money.minorUnits.magnitudeClamped, currency: money.currency) }
        return money.currency == base ? MoneyFormatter.spoken(value) : MoneyFormatter.spoken(value, base: base, rate: rate)
    }

    var color: Color {
        switch style {
        case .plain, .outflow: UZColor.label
        case .inflow: UZColor.positive
        case .transfer: UZColor.label2
        }
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: UZSpacing.xxs) {
            Text(primaryText)
                .font(font)
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText(value: Double(money.minorUnits)))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let secondaryText {
                Text(secondaryText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(UZColor.label2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }
}

extension Int64 {
    /// Absolute value that never traps on Int64.min.
    var magnitudeClamped: Int64 { self == .min ? .max : Swift.abs(self) }
}

extension EnvironmentValues {
    /// "Hide amounts" setting (DESIGN_SYSTEM §4); Settings toggle arrives in M10.
    @Entry public var uzHideAmounts: Bool = false
}

#Preview("Amounts") {
    VStack(alignment: .trailing, spacing: 16) {
        AmountText(Money(major: 484_800, .pkr), font: .system(size: 44, weight: .bold))
        AmountText(Money(minorUnits: 52_000, currency: .usd))
        AmountText(Money(major: 1_600, .pkr), style: .outflow)
        AmountText(Money(major: 75_000, .pkr), style: .inflow)
        AmountText(Money(major: 182_400, .pkr)).environment(\.uzHideAmounts, true)
    }
    .padding()
}
