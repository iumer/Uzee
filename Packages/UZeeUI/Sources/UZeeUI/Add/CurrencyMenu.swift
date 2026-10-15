import SwiftUI
import UZeeCore

/// The currency sign in front of an amount, as a menu (owner, 2026-10-15): a loan someone else paid had been
/// saved in the dollars of a hidden account, and editing it turned it into rupees. The sign always shows the
/// currency the amount will be saved in, and tapping it changes it.
struct CurrencyMenu: View {
    let ledger: LedgerSnapshot
    let currency: Currency
    var size: CGFloat = 30
    let choose: (Currency) -> Void

    /// Your base currency first, then the ones your accounts use, then the other known ones.
    private var choices: [Currency] {
        var list = [ledger.base]
        for account in ledger.activeAccounts where !list.contains(account.currency) { list.append(account.currency) }
        for known in Currency.known where !list.contains(known) { list.append(known) }
        return list
    }

    var body: some View {
        Menu {
            ForEach(choices, id: \.code) { choice in
                Button { choose(choice) } label: {
                    if choice == currency { Label("\(choice.code) (\(choice.symbol))", systemImage: "checkmark") }
                    else { Text("\(choice.code) (\(choice.symbol))") }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(currency.symbol)
                    .font(.system(size: size, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.down").font(.system(size: size * 0.4, weight: .bold))
            }
            .foregroundStyle(UZColor.tint)
        }
        .accessibilityLabel("Currency, \(currency.code)")
        .accessibilityIdentifier("currency.menu")
    }
}
