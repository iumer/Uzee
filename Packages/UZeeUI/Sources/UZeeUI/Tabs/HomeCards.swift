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
            spentCard
            comingUp
            peopleRow
        }
    }

    private var base: Currency { session.ledger.base }
    private var today: LocalDate { model.today }

    // MARK: Spent this month

    private var spentCard: some View {
        let budget = BudgetModel(session: session)
        let summary = budget.summary(for: budget.current)
        let spent = summary?.spent
            ?? ReportCalculator.monthToDate(session.transactions, today: today, base: base, rates: session.ledger.rates).now
        let monthName = today.startDate(in: .current).formatted(.dateTime.month(.wide))
        let daysLeft = today.days(to: budget.current.end) + 1
        return Button {
            session.open(.budget)
        } label: {
            UZCard {
                VStack(alignment: .leading, spacing: UZSpacing.s) {
                    HStack {
                        Text("Spent in \(monthName)").font(.subheadline).foregroundStyle(UZColor.label2)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(UZColor.label3)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: UZSpacing.s) {
                        Text(MoneyFormatter.string(spent)).font(.system(.title, weight: .bold)).monospacedDigit()
                            .minimumScaleFactor(0.7).lineLimit(1)
                        if let summary {
                            Text("of \(MoneyFormatter.string(summary.total))").font(.subheadline).foregroundStyle(UZColor.label2)
                                .lineLimit(1)
                        }
                    }
                    if let summary {
                        let total = Double(summary.total.minorUnits)
                        ProgressBarView(fraction: total > 0 ? Double(summary.spent.minorUnits) / total : 0,
                                        label: "\(MoneyFormatter.string(summary.spent)) of \(MoneyFormatter.string(summary.total))")
                        if summary.isOver {
                            Text("Over budget by \(MoneyFormatter.string((try? summary.left.negated()) ?? summary.left))")
                                .font(.footnote.weight(.semibold)).foregroundStyle(UZColor.negative)
                        } else {
                            Text("\(MoneyFormatter.string(summary.left)) left for \(daysLeft) \(daysLeft == 1 ? "day" : "days")")
                                .font(.footnote).foregroundStyle(UZColor.label2)
                        }
                    } else {
                        Text("No budget yet · tap to set one").font(.footnote).foregroundStyle(UZColor.label2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.budget")
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
                        Text("\(row.item.name) is overdue · \(MoneyFormatter.string(row.occurrence.amount))")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(UZColor.negative).lineLimit(2)
                        Spacer()
                        Button("Pay") { paying = row.occurrence }
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
