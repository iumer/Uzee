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
                    haveCard
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

    /// "You have Rs 484,800 · In 9 accounts"; opens the account list.
    private var haveCard: some View {
        let count = session.ledger.activeAccounts.count
        return NavigationLink(value: Route.accounts) {
            UZCard {
                VStack(alignment: .leading, spacing: UZSpacing.xs) {
                    HStack {
                        Text("You have").font(.subheadline).foregroundStyle(UZColor.label2)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(UZColor.label3)
                    }
                    AmountText(session.ledger.available, font: .system(.largeTitle, weight: .bold))
                        .accessibilityIdentifier("home.available")
                    Text(count == 1 ? "In 1 account" : "In \(count) accounts").font(.footnote).foregroundStyle(UZColor.label2)
                    if let footnote = session.ledger.footnote {
                        Text(footnote).font(.caption).foregroundStyle(UZColor.label2)
                            .accessibilityIdentifier("home.footnote")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
