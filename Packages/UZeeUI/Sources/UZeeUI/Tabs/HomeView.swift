import SwiftUI
import UZeeCore

/// Home (SCR-02, AUD-02): what needs attention, what's available, budget left, what's due before salary,
/// the next 7 days, people balances, where the money went this month, insights and accounts.
struct HomeView: View {
    @Bindable var session: AppSession
    @State private var isAddingAccount = false
    @State private var paying: Occurrence?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UZSpacing.xl) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(UZColor.label2)
                    .accessibilityIdentifier("home.date")
                if !session.isDatabaseReady {
                    AlertStrip(.error, title: "Couldn't open your data",
                               message: "Close UZee and open it again. Nothing has been changed.")
                        .accessibilityIdentifier("home.databaseError")
                }
                if session.ledger.accounts.isEmpty {
                    UZCard {
                        VStack(spacing: UZSpacing.l) {
                            EmptyStateView("No accounts yet", systemImage: "building.columns",
                                           description: "Add the bank, wallet and USD accounts you use. Your balance and what's due before salary appear here.")
                            Button("Add account") { isAddingAccount = true }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("home.addAccount")
                        }
                    }
                    // .contain keeps child identifiers visible to UI tests.
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("home.empty")
                } else {
                    let model = RecurringModel(session: session)
                    overdueStrip(model)
                    availableCard
                    HomeCards(session: session, model: model, paying: $paying)
                    accountsCard
                }
            }
            .padding(.horizontal, UZSpacing.xxl)
            .padding(.bottom, UZSpacing.xxl)
        }
        .background(UZColor.bg)
        .navigationTitle("Home")
        .sheet(isPresented: $isAddingAccount) { AccountFormSheet(session: session, editing: nil) }
        .sheet(item: $paying) { MarkPaidSheet(session: session, occurrence: $0) }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    session.isVoicePresented = true
                } label: {
                    Image(systemName: "mic")
                }
                .accessibilityLabel("Ask UZee")
                .accessibilityIdentifier("home.voice")
                NavigationLink(value: Route.settings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("home.settings")
            }
        }
    }

    @ViewBuilder
    private func overdueStrip(_ model: RecurringModel) -> some View {
        let overdue = model.nextOccurrences.filter { $0.occurrence.state == .overdue }
        if let first = overdue.first {
            UZCard(padding: UZSpacing.l) {
                HStack(spacing: UZSpacing.l) {
                    Image(systemName: "exclamationmark.circle.fill").font(.title2).foregroundStyle(UZColor.negative)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                        Text(overdue.count == 1 ? "1 overdue" : "\(overdue.count) overdue")
                            .font(.caption.weight(.bold)).foregroundStyle(UZColor.negative)
                        Text("\(first.item.name) · \(MoneyFormatter.string(first.occurrence.amount))").font(.subheadline.weight(.semibold))
                        Text((first.item.isEstimated ? "Estimated · " : "") + "was due \(DateText.short(first.occurrence.scheduledDate))")
                            .font(.footnote).foregroundStyle(UZColor.label2)
                    }
                    Spacer()
                    Button("Pay") { paying = first.occurrence }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityIdentifier("home.payOverdue")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.overdue")
        }
    }

    private var availableCard: some View {
        UZCard {
            VStack(alignment: .leading, spacing: UZSpacing.s) {
                Text("Available balance").font(.subheadline.weight(.semibold)).foregroundStyle(UZColor.label2)
                AmountText(session.ledger.available, font: .system(.largeTitle, weight: .bold))
                    .accessibilityIdentifier("home.available")
                if let footnote = session.ledger.footnote {
                    Text(footnote).font(.caption).foregroundStyle(UZColor.label2)
                        .accessibilityIdentifier("home.footnote")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var accountsCard: some View {
        VStack(alignment: .leading, spacing: UZSpacing.m) {
            HStack {
                SectionHeader("Accounts")
                Spacer()
                NavigationLink("See all", value: Route.accounts)
                    .font(.subheadline)
                    .accessibilityIdentifier("home.accounts")
            }
            UZCard(padding: UZSpacing.xxl) {
                VStack(spacing: 0) {
                    let shown = session.ledger.activeAccounts
                    ForEach(shown) { account in
                        NavigationLink(value: Route.account(account.id)) {
                            AccountRow(account: account, ledger: session.ledger)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("account.\(account.name)")
                        if account.id != shown.last?.id { Divider() }
                    }
                }
            }
        }
    }
}
