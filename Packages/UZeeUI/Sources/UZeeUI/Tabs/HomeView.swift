import Charts
import SwiftUI
import UZeeCore

/// Home (round 3 mockup M, owner pick 2026-10-12): four things only. What you have, what you spent,
/// what's coming up, and who owes whom.
struct HomeView: View {
    @Bindable var session: AppSession
    @State private var isAddingAccount = false
    @State private var paying: Occurrence?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UZSpacing.l) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline)
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
                    TopUpCard(session: session)
                    moneyTile
                    HomeCards(session: session, model: RecurringModel(session: session), paying: $paying)
                    if session.prayer.hasPlace { PrayerHomeCard(session: session) }
                }
            }
            .padding(.horizontal, UZSpacing.xxl)
            .padding(.bottom, UZSpacing.xxl)
        }
        .background(UZColor.bg)
        .navigationTitle("Home")
        .sheet(isPresented: $isAddingAccount) { AccountFormSheet(session: session, editing: nil) }
        .sheet(item: $paying) { MarkPaidSheet(session: session, occurrence: $0) }
    }

    /// Where the money sits: one slice per account, biggest first (owner, 2026-10-12).
    private var accountsRing: some View {
        let shares = accountShares
        let count = session.ledger.activeAccounts.count
        return ZStack {
            Chart(Array(shares.enumerated()), id: \.offset) { item in
                SectorMark(angle: .value("Balance", item.element.value), innerRadius: .ratio(0.7), angularInset: 1.5)
                    .cornerRadius(2)
                    .foregroundStyle(HomeCards.palette[item.offset % HomeCards.palette.count])
            }
            .chartLegend(.hidden)
            VStack(spacing: 0) {
                Text("\(count)").font(.headline).monospacedDigit()
                Text(count == 1 ? "account" : "accounts").font(.caption2).foregroundStyle(UZColor.label2)
            }
        }
        .frame(width: HomeCards.ringSize, height: HomeCards.ringSize)
        .accessibilityLabel(shares.prefix(4).map(\.name).joined(separator: ", "))
    }

    private var accountShares: [(name: String, value: Double)] {
        let ledger = session.ledger
        return ledger.activeAccounts.compactMap { account -> (name: String, value: Double)? in
            let amount = NSDecimalNumber(decimal: ledger.balance(of: account).decimalValue).doubleValue
            let rate = account.currency == ledger.base ? 1 : NSDecimalNumber(decimal: ledger.rate(for: account.currency)).doubleValue
            let value = amount * rate
            return value > 0 ? (account.name, value) : nil
        }
        .sorted { $0.value > $1.value }
    }

    /// One tile with two circles side by side: what you have and what you spent this month
    /// (owner, 2026-10-12: two separate tiles didn't look neat). Each half opens its own screen.
    private var moneyTile: some View {
        UZCard {
            HStack(alignment: .top, spacing: UZSpacing.l) {
                haveHalf
                Divider()
                SpentHalf(session: session)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.moneyTile")
    }

    /// "You have Rs 484,800" with a ring by account; opens the account list.
    private var haveHalf: some View {
        NavigationLink(value: Route.accounts) {
            VStack(spacing: UZSpacing.s) {
                Text("You have").font(.subheadline).foregroundStyle(UZColor.label2)
                accountsRing
                AmountText(session.ledger.available, font: .system(.title3, weight: .bold))
                    .minimumScaleFactor(0.5).lineLimit(1)
                    .accessibilityIdentifier("home.available")
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.accounts")
    }
}

/// Home: the prayer now and when it ends, once namaz times are set up; opens Namaz & Qibla.
struct PrayerHomeCard: View {
    @Bindable var session: AppSession

    var body: some View {
        // A value link, so the Home path knows a screen is open and the floating UZee and "+" step aside.
        NavigationLink(value: Route.prayer) {
            TimelineView(.everyMinute) { context in
                let now = context.date
                let windows = session.prayer.windows(LocalDate(now, in: .current), timeZone: .current)
                let current = windows.first { $0.contains(now) }
                let next = windows.first { $0.start > now }
                UZCard(padding: UZSpacing.l) {
                    HStack(spacing: UZSpacing.l) {
                        Image(systemName: "moon.stars.fill").font(.title3).foregroundStyle(UZColor.tint).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                            if let current {
                                Text("\(current.prayer.name) · now").font(.subheadline.weight(.semibold))
                                Text("Ends \(current.end.formatted(date: .omitted, time: .shortened))"
                                     + (next.map { " · \($0.prayer.name) at \($0.start.formatted(date: .omitted, time: .shortened))" } ?? ""))
                                    .font(.caption).foregroundStyle(UZColor.label2)
                            } else if let next {
                                Text("Next: \(next.prayer.name)").font(.subheadline.weight(.semibold))
                                Text("At \(next.start.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(UZColor.label2)
                            } else {
                                Text("Namaz & Qibla").font(.subheadline.weight(.semibold))
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(UZColor.label3)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.prayer")
    }
}
