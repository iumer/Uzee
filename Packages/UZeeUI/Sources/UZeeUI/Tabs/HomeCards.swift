import Charts
import SwiftUI
import UZeeCore

/// Home after "You have" (round 3 mockup M): what you spent against the budget, what's coming up, and who
/// owes whom. Insights and Where it went moved to Plan › Budget; Until next salary lives in Plan › Calendar.
struct HomeCards: View {
    @Bindable var session: AppSession
    let model: RecurringModel
    @Binding var paying: Occurrence?

    var body: some View {
        VStack(alignment: .leading, spacing: UZSpacing.l) {
            whereItWent
            comingUp
            peopleRow
        }
    }

    private var base: Currency { session.ledger.base }
    private var today: LocalDate { model.today }

    // MARK: Where it went

    static let ringSize: CGFloat = 96
    static let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .yellow, .indigo, .mint, .gray]

    /// The big circle: this month's spending by category (owner, 2026-10-12). Opens Reports.
    @ViewBuilder
    private var whereItWent: some View {
        let shares = ReportCalculator.byGroup(session.transactions, from: today.firstOfMonth, through: today.lastOfMonth,
                                              categories: session.ledger.categories, base: base, rates: session.ledger.rates)
        if !shares.isEmpty {
            let month = today.startDate(in: .current).formatted(.dateTime.month(.wide))
            Button {
                session.paths[.home, default: []].append(.reports)
            } label: {
                UZCard {
                    VStack(alignment: .leading, spacing: UZSpacing.l) {
                        Text("Where it went in \(month)").font(.headline).foregroundStyle(UZColor.label)
                        HStack(spacing: UZSpacing.xxl) {
                            Chart(shares) { share in
                                SectorMark(angle: .value("Amount", Double(share.amount.minorUnits)), innerRadius: .ratio(0.6), angularInset: 1.5)
                                    .cornerRadius(3)
                                    .foregroundStyle(color(share.categoryID))
                            }
                            .chartLegend(.hidden)
                            .frame(width: 140, height: 140)
                            .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: UZSpacing.s) {
                                ForEach(shares.prefix(6)) { share in
                                    HStack(spacing: UZSpacing.s) {
                                        Circle().fill(color(share.categoryID)).frame(width: 8, height: 8)
                                        Text(session.ledger.category(share.categoryID)?.name ?? "Other").font(.footnote).lineLimit(1)
                                        Spacer(minLength: 0)
                                        Text("\(share.percent)%").font(.footnote.weight(.semibold)).monospacedDigit()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(shares.prefix(6).map { "\(session.ledger.category($0.categoryID)?.name ?? "Other") \($0.percent) percent" }
                                    .joined(separator: ", "))
            .accessibilityIdentifier("home.whereItWent")
        }
    }

    private func color(_ id: UUID) -> Color {
        session.ledger.category(id).map { CategoryStyle($0.group).color } ?? UZColor.label3
    }

    // MARK: Coming up

    @ViewBuilder
    private var comingUp: some View {
        let overdue = model.nextOccurrences.filter { $0.occurrence.state == .overdue }
        let rows = model.due(from: today, through: today.addingDays(13))
            .filter { !$0.occurrence.isResolved && $0.occurrence.state != .overdue }
            .prefix(max(1, 3 - overdue.count))
        UZCard(padding: UZSpacing.l) {
            VStack(alignment: .leading, spacing: UZSpacing.m) {
                HStack {
                    Text("Coming up").font(.headline)
                    Spacer()
                    Button("See all") { session.open(.calendar) }
                        .font(.subheadline)
                        .accessibilityIdentifier("home.upcomingAll")
                }
                ForEach(overdue.prefix(2)) { row in
                    HStack(spacing: UZSpacing.m) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(UZColor.negative).accessibilityHidden(true)
                        // Income isn't "overdue" or paid: it hasn't come yet, and you mark it received (owner, 2026-10-22).
                        Text(row.item.type.isIncome ? "\(row.item.name) hasn't come yet · \(MoneyFormatter.string(row.occurrence.amount))"
                             : "\(row.item.name) is overdue · \(MoneyFormatter.string(row.occurrence.amount))")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(UZColor.negative).lineLimit(2)
                        Spacer()
                        Button(row.item.type.isIncome ? "Received" : "Pay") { paying = row.occurrence }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                            .accessibilityIdentifier(row.id == overdue.first?.id ? "home.payOverdue" : "home.pay.\(row.item.name)")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("home.overdue")
                }
                if overdue.isEmpty && rows.isEmpty {
                    Text("Nothing due in the next 2 weeks.").font(.subheadline).foregroundStyle(UZColor.label2)
                }
                ForEach(Array(rows)) { row in
                    Button { paying = row.occurrence } label: {
                        HStack(spacing: UZSpacing.l) {
                            VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                                Text(row.item.name).foregroundStyle(UZColor.label).lineLimit(1)
                                Text(DateText.relative(row.occurrence.dueDate, today: today)).font(.footnote).foregroundStyle(UZColor.label2)
                            }
                            Spacer()
                            Text(MoneyFormatter.string(row.occurrence.amount)).font(.subheadline.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(row.item.type.isIncome ? UZColor.positive : UZColor.label)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.upcoming.\(row.item.name)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.comingUp")
    }

    // MARK: People

    @ViewBuilder
    private var peopleRow: some View {
        let overall = session.balances.overall
        if !session.people.others.isEmpty {
            Button {
                session.selectedTab = .people
            } label: {
                UZCard(padding: UZSpacing.l) {
                    HStack(spacing: UZSpacing.s) {
                        let owed = Text(MoneyFormatter.string(overall.owedToYou)).bold().foregroundStyle(UZColor.positive)
                        let owe = Text(MoneyFormatter.string(overall.youOwe)).bold().foregroundStyle(UZColor.negative)
                        Text("People owe you \(owed) · you owe \(owe)")
                            .font(.subheadline).foregroundStyle(UZColor.label)
                            .lineLimit(2).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(UZColor.label3)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.people")
        }
    }
}

/// Home tile, right half: spent this month with a ring of how much of the budget is used; opens Plan › Budget.
struct SpentHalf: View {
    @Bindable var session: AppSession

    var body: some View {
        let budget = BudgetModel(session: session)
        let today = budget.today
        let summary = budget.summary(for: budget.current)
        let spent = summary?.spent
            ?? ReportCalculator.monthToDate(session.transactions, today: today, base: session.ledger.base, rates: session.ledger.rates).now
        let monthName = today.startDate(in: .current).formatted(.dateTime.month(.wide))
        let daysLeft = today.days(to: budget.current.end) + 1
        Button {
            session.open(.budget)
        } label: {
            VStack(spacing: UZSpacing.s) {
                Text(budget.isCustom ? "Spent this period" : "Spent in \(monthName)").font(.subheadline).foregroundStyle(UZColor.label2).lineLimit(1)
                if let summary {
                    let total = Double(summary.total.minorUnits)
                    ProgressRingView(remaining: total > 0 ? 1 - Double(summary.spent.minorUnits) / total : 1,
                                     label: "\(BudgetCalculator.percentText(summary.usedBasisPoints)) of the budget used") {
                        VStack(spacing: 0) {
                            Text(BudgetCalculator.percentText(summary.usedBasisPoints)).font(.headline).monospacedDigit()
                            Text("used").font(.caption2).foregroundStyle(UZColor.label2)
                        }
                    }
                    .frame(width: HomeCards.ringSize, height: HomeCards.ringSize)
                } else {
                    ZStack {
                        Circle().stroke(UZColor.label3.opacity(0.3), lineWidth: 10)
                        Text("Set\nbudget").font(.caption.weight(.semibold)).foregroundStyle(UZColor.tint).multilineTextAlignment(.center)
                    }
                    .padding(5)
                    .frame(width: HomeCards.ringSize, height: HomeCards.ringSize)
                }
                Text(MoneyFormatter.string(spent)).font(.system(.title3, weight: .bold)).monospacedDigit()
                    .minimumScaleFactor(0.5).lineLimit(1)
                if let summary {
                    if summary.isOver {
                        Text("Over budget by \(MoneyFormatter.string((try? summary.left.negated()) ?? summary.left))")
                            .font(.caption.weight(.semibold)).foregroundStyle(UZColor.negative).lineLimit(1).minimumScaleFactor(0.7)
                    } else {
                        // "of budget", not of your money (owner, 2026-10-22: "I have 500k, why only 130k left?").
                        Text("\(MoneyFormatter.string(summary.left)) of budget left · \(daysLeft) \(daysLeft == 1 ? "day" : "days")")
                            .font(.caption).foregroundStyle(UZColor.label2).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.budget")
    }
}
