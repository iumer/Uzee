import SwiftUI
import UZeeCore

/// Home (SCR-02). M2: available balance and accounts; due items, budget and people cards arrive in M4–M8.
struct HomeView: View {
    @Bindable var session: AppSession
    @State private var isAddingAccount = false

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
                    .accessibilityIdentifier("home.empty")
                } else {
                    availableCard
                    accountsCard
                }
            }
            .padding(.horizontal, UZSpacing.xxl)
            .padding(.bottom, UZSpacing.xxl)
        }
        .background(UZColor.bg)
        .navigationTitle("Home")
        .sheet(isPresented: $isAddingAccount) { AccountFormSheet(session: session, editing: nil) }
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

    private var availableCard: some View {
        UZCard {
            VStack(alignment: .leading, spacing: UZSpacing.s) {
                Text("Available").font(.subheadline.weight(.semibold)).foregroundStyle(UZColor.label2)
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
                        if account.id != shown.last?.id { Divider() }
                    }
                }
            }
        }
    }
}
