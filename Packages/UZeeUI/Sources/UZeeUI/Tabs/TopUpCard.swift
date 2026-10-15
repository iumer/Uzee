import SwiftUI
import UZeeCore

/// On Home: "Top up Meezan: Netflix Rs 1,100 is due tomorrow and it has Rs 500" (owner, 2026-10-15).
struct TopUpCard: View {
    @Bindable var session: AppSession

    var body: some View {
        let warnings = session.topUpWarnings
        if !warnings.isEmpty {
            UZCard(tint: UZColor.warning) {
                VStack(alignment: .leading, spacing: UZSpacing.m) {
                    Label("Top up needed", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline).foregroundStyle(UZColor.warning)
                    ForEach(warnings) { warning in
                        NavigationLink(value: Route.account(warning.accountID)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add \(MoneyFormatter.string(warning.shortBy)) to \(warning.accountName)")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(UZColor.label)
                                Text("\(warning.itemName) \(MoneyFormatter.string(warning.amount)) is due \(warning.dueDate.listTitle(today: session.today)); it has \(MoneyFormatter.string(warning.balance)).")
                                    .font(.footnote).foregroundStyle(UZColor.label2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.topUp")
        }
    }
}
