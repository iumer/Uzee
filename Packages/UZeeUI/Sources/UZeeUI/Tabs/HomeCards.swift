import Charts
import SwiftUI
import UZeeCore

/// The Home cards after the available balance (SCR-02): budget left and spent this month, until next salary,
/// the next 7 days, people balances, where it went and the last full month's insight.
struct HomeCards: View {
    @Bindable var session: AppSession
    let model: RecurringModel
    @Binding var paying: Occurrence?

    var body: some View {
        VStack(alignment: .leading, spacing: UZSpacing.xl) {
            budgetRow
            salaryCard
            upcoming
            peopleRow
            whereItWent
            insights
        }
    }

    private var base: Currency { session.ledger.base }
    private var today: LocalDate { model.today }

    // MARK: Budget and spending

    private var budgetRow: some View {
        let budget = BudgetModel(session: session)
        let summary = budget.summary(for: budget.current)
        let spent = ReportCalculator.monthToDate(session.transactions, today: today, base: base, rates: session.ledger.rates)
        let monthName = today.startDate(in: .current).formatted(.dateTime.month(.wide))
        let previousName = today.firstOfMonth.addingMonths(-1).startDate(in: .current).formatted(.dateTime.month(.wide))
        return HStack(alignment: .top, spacing: UZSpacing.l) {
            Button {
                session.selectedTab = .budget
            } label: {
                UZCard(padding: UZSpacing.l) {
                    VStack(alignment: .leading, spacing: UZSpacing.xs) {
                        Text("Budget left").font(.footnote.weight(.semibold)).foregroundStyle(UZColor.label2)
                        if let summary {
                            Text(MoneyFormatter.string(summary.isOver ? ((try? summary.left.negated()) ?? summary.left) : summary.left))
                                .font(.title3.bold()).monospacedDigit()
                                .foregroundStyle(summary.isOver ? UZColor.negative : UZColor.label)
                                .minimumScaleFactor(0.7).lineLimit(1)
                            Text("of \(MoneyFormatter.string(summary.total)) · \(BudgetCalculator.percentText(summary.usedBasisPoints)) used")
                                .font(.caption).foregroundStyle(UZColor.label2)
                            if let over = summary.lines.first(where: { $0.overBy != nil }), let amount = over.overBy {
                                Label("\(session.ledger.category(over.categoryID)?.name ?? "A category") over by \(MoneyFormatter.string(amount))",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption.weight(.semibold)).foregroundStyle(UZColor.warning)
                            }
                        } else {
                            Text("Not set").font(.title3.bold())
                            Text("Tap to set a budget").font(.caption).foregroundStyle(UZColor.label2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.budget")
            Button {
                session.selectedTab = .activity
            } label: {
                UZCard(padding: UZSpacing.l) {
                    VStack(alignment: .leading, spacing: UZSpacing.xs) {
                        Text("Spent in \(monthName)").font(.footnote.weight(.semibold)).foregroundStyle(UZColor.label2)
                        Text(MoneyFormatter.string(spent.now)).font(.title3.bold()).monospacedDigit()
                            .minimumScaleFactor(0.7).lineLimit(1)
                        let difference = spent.now.minorUnits - spent.before.minorUnits
                        let amount = MoneyFormatter.string(Money(minorUnits: difference.magnitudeClamped, currency: base))
                        if spent.before.minorUnits == 0 && spent.now.minorUnits == 0 {
                            Text("Nothing spent yet").font(.caption).foregroundStyle(UZColor.label2)
                        } else if difference == 0 {
                            Text("Same as this time in \(previousName)").font(.caption).foregroundStyle(UZColor.label2)
                        } else {
                            Text(difference < 0 ? "\(amount) less than this time in \(previousName)"
                                                : "\(amount) more than this time in \(previousName)")
                                .font(.caption).foregroundStyle(difference < 0 ? UZColor.positive : UZColor.warning)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.spent")
        }
    }

    // MARK: Until next salary

    @ViewBuilder
    private var salaryCard: some View {
        if let salary = model.nextSalary, salary.dueDate > today {
            let rows = model.due(from: today, through: salary.dueDate.addingDays(-1), includeOverdue: true)
                .filter { !$0.item.type.isIncome && !$0.occurrence.isResolved }
            let due = model.total(rows)
            let left = (try? session.ledger.available.subtracting(due)) ?? session.ledger.available
            let days = today.days(to: salary.dueDate)
            let hasOverdue = rows.contains { $0.occurrence.state == .overdue }
            Button {
                session.selectedTab = .calendar
            } label: {
                UZCard {
                    VStack(alignment: .leading, spacing: UZSpacing.m) {
                        HStack {
                            Text("Until next salary").font(.subheadline.weight(.semibold)).foregroundStyle(UZColor.label2)
                            Spacer()
                            Text("\(days) \(days == 1 ? "day" : "days") · \(DateText.short(salary.dueDate))")
                                .font(.subheadline.weight(.semibold))
                        }
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Due").font(.caption).foregroundStyle(UZColor.label2)
                                Text(MoneyFormatter.string(due)).font(.title3.bold()).monospacedDigit()
                                    .accessibilityIdentifier("home.dueBeforeSalary")
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 0) {
                                Text("Left after bills").font(.caption).foregroundStyle(UZColor.label2)
                                Text(MoneyFormatter.string(left)).font(.title3.bold()).monospacedDigit()
                                    .foregroundStyle(left.isNegative ? UZColor.negative : UZColor.positive)
                                    .accessibilityIdentifier("home.leftAfterBills")
                            }
                        }
                        Text((hasOverdue ? "Due includes overdue bills · " : "") + "your shares · USD at $1 = Rs 280")
                            .font(.caption).foregroundStyle(UZColor.label2)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.salary")
        }
    }

    // MARK: Next 7 days

    @ViewBuilder
    private var upcoming: some View {
        let rows = model.due(from: today, through: today.addingDays(6)).filter { !$0.occurrence.isResolved && $0.occurrence.state != .overdue }
        VStack(alignment: .leading, spacing: UZSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("Upcoming")
                Text("next 7 days").font(.subheadline).foregroundStyle(UZColor.label2).fixedSize()
                Spacer()
                Button("See all") { session.selectedTab = .calendar }
                    .font(.subheadline)
                    .accessibilityIdentifier("home.upcomingAll")
            }
            UZCard(padding: UZSpacing.l) {
                VStack(alignment: .leading, spacing: UZSpacing.l) {
                    if rows.isEmpty {
                        Text("Nothing due in the next 7 days.").foregroundStyle(UZColor.label2)
                    }
                    ForEach(rows) { row in
                        HStack(spacing: UZSpacing.l) {
                            VStack(spacing: 0) {
                                Text(row.occurrence.dueDate.startDate(in: .current).formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.caption2).foregroundStyle(UZColor.label2)
                                Text("\(row.occurrence.dueDate.day)").font(.headline).monospacedDigit()
                            }
                            .frame(width: 34)
                            VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                                Text(row.item.name).lineLimit(1)
                                Text(DateText.relative(row.occurrence.dueDate, today: today)).font(.footnote).foregroundStyle(UZColor.label2)
                            }
                            Spacer()
                            Text(MoneyFormatter.string(row.occurrence.amount)).font(.subheadline.weight(.semibold)).monospacedDigit()
                            Button(row.item.type.isIncome ? "Got it" : "Pay") { paying = row.occurrence }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("home.upcoming.\(row.item.name)")
                    }
                }
            }
        }
    }

    // MARK: People

    private var peopleRow: some View {
        let overall = session.balances.overall
        let owing = names(owesMe: true)
        let owed = names(owesMe: false)
        return HStack(alignment: .top, spacing: UZSpacing.l) {
            peopleCard("Owed to you", overall.owedToYou, owing.isEmpty ? "No one owes you" : "\(owing) owe you", positive: true)
                .accessibilityIdentifier("home.owedToYou")
            peopleCard("You owe", overall.youOwe, owed.isEmpty ? "You owe no one" : "You owe \(owed)", positive: false)
                .accessibilityIdentifier("home.youOwe")
        }
    }

    private func names(owesMe: Bool) -> String {
        let people = session.people.others
            .map { ($0.name, session.balances.net(of: $0.id)) }
            .filter { owesMe ? $0.1.minorUnits > 0 : $0.1.minorUnits < 0 }
            .sorted { $0.1.minorUnits.magnitudeClamped > $1.1.minorUnits.magnitudeClamped }
            .map(\.0)
        switch people.count {
        case 0: return ""
        case 1: return people[0]
        case 2: return "\(people[0]) and \(people[1])"
        default: return people.prefix(people.count - 1).joined(separator: ", ") + " and " + people[people.count - 1]
        }
    }

    private func peopleCard(_ title: String, _ amount: Money, _ line: String, positive: Bool) -> some View {
        Button {
            session.selectedTab = .people
        } label: {
            UZCard(padding: UZSpacing.l) {
                VStack(alignment: .leading, spacing: UZSpacing.xs) {
                    Text(title).font(.footnote.weight(.semibold)).foregroundStyle(UZColor.label2)
                    Text(MoneyFormatter.string(amount)).font(.title3.bold()).monospacedDigit()
                        .foregroundStyle(amount.isZero ? UZColor.label : positive ? UZColor.positive : UZColor.negative)
                    Text(line).font(.caption).foregroundStyle(UZColor.label2).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: Where it went

    @ViewBuilder
    private var whereItWent: some View {
        let shares = ReportCalculator.byGroup(session.transactions, from: today.firstOfMonth, through: today.lastOfMonth,
                                              categories: session.ledger.categories, base: base, rates: session.ledger.rates)
        if !shares.isEmpty {
            let month = today.startDate(in: .current).formatted(.dateTime.month(.abbreviated))
            VStack(alignment: .leading, spacing: UZSpacing.m) {
                SectionHeader("Where it went · \(month)")
                Button {
                    session.paths[.home, default: []].append(.reports)
                } label: {
                    UZCard {
                        HStack(spacing: UZSpacing.xxl) {
                            Chart(shares) { share in
                                SectorMark(angle: .value("Amount", Double(share.amount.minorUnits)), innerRadius: .ratio(0.62), angularInset: 1.5)
                                    .foregroundStyle(color(share.categoryID))
                            }
                            .frame(width: 110, height: 110)
                            .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: UZSpacing.xs) {
                                ForEach(shares.prefix(6)) { share in
                                    HStack(spacing: UZSpacing.s) {
                                        Circle().fill(color(share.categoryID)).frame(width: 8, height: 8)
                                        Text(session.ledger.category(share.categoryID)?.name ?? "Other").font(.footnote).lineLimit(1)
                                        Spacer()
                                        Text("\(share.percent)%").font(.footnote.weight(.semibold)).monospacedDigit()
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
    }

    private func color(_ id: UUID) -> Color {
        session.ledger.category(id).map { CategoryStyle($0.group).color } ?? UZColor.label3
    }

    // MARK: Insights

    private var insights: some View {
        let last = today.firstOfMonth.addingMonths(-1)
        let totals = ReportCalculator.totals(session.transactions, from: last, through: last.lastOfMonth, base: base, rates: session.ledger.rates)
        let net = (try? totals.income.subtracting(totals.spending)) ?? .zero(base)
        let name = last.startDate(in: .current).formatted(.dateTime.month(.wide))
        return VStack(alignment: .leading, spacing: UZSpacing.m) {
            SectionHeader("Insights")
            NavigationLink(value: Route.reports) {
                UZCard(padding: UZSpacing.l) {
                    HStack {
                        Image(systemName: "chart.bar.xaxis").font(.title3).foregroundStyle(UZColor.tint).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                            Text(totals.income.isZero && totals.spending.isZero ? "\(name) · nothing yet" : "\(name) · net \(MoneyFormatter.string(net, sign: .always))").font(.subheadline.weight(.semibold))
                            Text("Income \(MoneyFormatter.string(totals.income)) · spending \(MoneyFormatter.string(totals.spending))")
                                .font(.caption).foregroundStyle(UZColor.label2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(UZColor.label3)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.insights")
        }
    }
}
