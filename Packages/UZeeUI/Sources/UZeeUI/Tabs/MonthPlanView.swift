import SwiftUI
import UZeeCore

/// Plan › Month (owner, 2026-10-15, like their Google Sheet): what comes in this month, what has to go out, and
/// what's left. Both lists are your repeating items (salary, rent you get, bills, kameti, installments, money you
/// send home every month), so adding a line here adds it to the calendar with reminders too.
struct MonthPlanView: View {
    @Bindable var session: AppSession
    @State private var month: LocalDate?
    @State private var adding: RecurringItem?

    private struct Line: Identifiable {
        let due: DueItem
        let share: Money
        var id: String { due.id }
    }

    var body: some View {
        let model = RecurringModel(session: session)
        let first = (month ?? session.today).firstOfMonth
        let rows = lines(model, first: first)
        let incoming = rows.filter { $0.due.item.type.isIncome }
        let outgoing = rows.filter { !$0.due.item.type.isIncome }
        let inTotal = sum(incoming, model)
        let outTotal = sum(outgoing, model)
        let left = (try? inTotal.subtracting(outTotal)) ?? .zero(model.base)
        let stillToPay = sum(outgoing.filter { !$0.due.occurrence.isResolved }, model)
        ScrollView {
            VStack(alignment: .leading, spacing: UZSpacing.xl) {
                PlanSwitch(session: session)
                monthHeader(first)
                UZCard {
                    VStack(alignment: .leading, spacing: UZSpacing.m) {
                        figure("Coming in", inTotal, color: UZColor.positive)
                        figure("Going out", outTotal, color: UZColor.label)
                        Divider()
                        HStack(alignment: .firstTextBaseline) {
                            Text(left.isNegative ? "Short by" : "Left").font(.title3.weight(.semibold))
                            Spacer()
                            Text(MoneyFormatter.string(Money(minorUnits: left.minorUnits.magnitudeClamped, currency: left.currency)))
                                .font(.title2.weight(.bold)).monospacedDigit()
                                .foregroundStyle(left.isNegative ? UZColor.negative : UZColor.positive)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("monthPlan.left")
                        if !stillToPay.isZero {
                            Text("\(MoneyFormatter.string(stillToPay)) still to pay this month")
                                .font(.footnote).foregroundStyle(UZColor.label2)
                        }
                    }
                }
                section("Coming in", incoming, model: model, empty: "Add your salary and any money you get every month.",
                        add: "Add money coming in", type: .salary, first: first)
                section("Going out", outgoing, model: model, empty: "Add rent, bills, kameti, installments, money you send home…",
                        add: "Add a payment", type: .bill, first: first)
                Text("Left is what comes in minus what goes out this month, counting what's already paid. "
                     + "Each line repeats on its own schedule and shows on the calendar with a reminder. Your shares only.")
                    .font(.caption).foregroundStyle(UZColor.label2)
            }
            .padding(.horizontal, UZSpacing.xxl)
            .padding(.bottom, 96)
        }
        .background(UZColor.bg)
        .navigationTitle("Plan")
        .sheet(item: $adding) { RecurringFormSheet(session: session, item: nil, draft: $0) }
        .accessibilityIdentifier("screen.monthPlan")
    }

    /// Every occurrence this month, paid or not.
    private func lines(_ model: RecurringModel, first: LocalDate) -> [Line] {
        var result: [Line] = []
        for item in model.active {
            for occurrence in OccurrenceGenerator.occurrences(item, records: model.records(item), from: first, through: first.lastOfMonth,
                                                              today: model.today) where occurrence.state != .skipped {
                result.append(Line(due: DueItem(item: item, occurrence: occurrence), share: model.baseShare(item, occurrence.amount)))
            }
        }
        return result.sorted { RecurringModel.order($0.due, $1.due) }
    }

    private func sum(_ lines: [Line], _ model: RecurringModel) -> Money {
        (try? Money.sum(lines.map(\.share), in: model.base)) ?? .zero(model.base)
    }

    private func monthHeader(_ first: LocalDate) -> some View {
        HStack {
            Button { month = first.addingMonths(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous month")
            Spacer()
            Text(DateText.monthYear(first)).font(.headline)
            Spacer()
            Button { month = first.addingMonths(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next month")
        }
        .accessibilityIdentifier("monthPlan.month")
    }

    private func figure(_ title: String, _ amount: Money, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(UZColor.label2)
            Spacer()
            Text(MoneyFormatter.string(amount)).font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }

    private func section(_ title: String, _ lines: [Line], model: RecurringModel, empty: String, add: String,
                         type: RecurringType, first: LocalDate) -> some View {
        VStack(alignment: .leading, spacing: UZSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title)
                Spacer()
                Text(MoneyFormatter.string(sum(lines, model))).font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(UZColor.label2)
            }
            UZCard(padding: UZSpacing.l) {
                VStack(alignment: .leading, spacing: UZSpacing.m) {
                    if lines.isEmpty {
                        Text(empty).font(.subheadline).foregroundStyle(UZColor.label2)
                    }
                    ForEach(lines) { line in
                        NavigationLink(value: Route.recurring(line.due.item.id)) {
                            RecurringRow(model: model, item: line.due.item, occurrence: line.due.occurrence, showsDate: true)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                    Button {
                        let day = min(session.today.day, first.daysInMonth)
                        let anchor = LocalDate(year: first.year, month: first.month, day: day)
                        adding = RecurringItem(name: "", type: type, amount: .zero(session.ledger.base),
                                               rule: RecurrenceRule(anchor: anchor), trackedFrom: anchor,
                                               colorHex: type.isIncome ? "#34C759" : "#5E5CE6")
                    } label: {
                        Label(add, systemImage: "plus.circle.fill").font(.subheadline.weight(.semibold))
                    }
                    .accessibilityIdentifier("monthPlan.add.\(type.rawValue)")
                }
            }
        }
    }
}
