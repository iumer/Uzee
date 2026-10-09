import SwiftUI
import UZeeCore

/// One thing on a calendar day: a bill occurrence or a loan coming due (CAL-01/02).
struct CalendarEntry: Identifiable {
    enum Kind { case bill, subscription, plan, income, people, event }

    let id: String
    let date: LocalDate
    let kind: Kind
    let name: String
    let meta: String
    let amount: Money
    /// Paid, skipped, overdue, due today, upcoming; nil for people items.
    let state: OccurrenceState?
    let occurrence: Occurrence?
    let route: Route?
    /// A custom entry (CAL-03), opened in its editor rather than pushed.
    var custom: UZeeCore.CalendarEvent? = nil

    var glyph: String {
        switch kind {
        case .bill: "square.fill"
        case .subscription: "circle.fill"
        case .plan: "diamond.fill"
        case .income: "triangle.fill"
        case .people: "circle"
        case .event: "star.fill"
        }
    }

    var color: Color {
        switch state {
        case .paid, .skipped: UZColor.label3
        case .overdue: UZColor.negative
        default:
            switch kind {
            case .bill: Color(hex: "#FFCC00")
            case .subscription: Color(hex: "#FF2D55")
            case .plan: Color(hex: "#00C7BE")
            case .income: UZColor.positive
            case .people: UZColor.tint
            case .event: Color(hex: "#AF52DE")
            }
        }
    }
}

/// Calendar (SCR-14, CAL-01…07): a month of bills, subscriptions, plans, income and loans due back,
/// with "Due before salary" up top, a day list, Mark paid from any row, and a link to Bills & subscriptions.
struct CalendarTabView: View {
    @Bindable var session: AppSession
    @State private var month: LocalDate?
    @State private var selected: LocalDate?
    @State private var showsAgenda = false
    @State private var paying: Occurrence?
    @State private var editingEvent: UZeeCore.CalendarEvent?
    @State private var addingEvent = false

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        let model = RecurringModel(session: session)
        let today = model.today
        let first = (month ?? today).firstOfMonth
        let events = events(from: first, through: first.lastOfMonth, model: model)
        ScrollView {
            VStack(alignment: .leading, spacing: UZSpacing.xl) {
                if first <= today && today <= first.lastOfMonth { salaryCard(model) }
                if showsAgenda {
                    agenda(events, model: model)
                } else {
                    UZCard(padding: UZSpacing.l) {
                        VStack(spacing: UZSpacing.m) {
                            monthHeader(first)
                            grid(first, events: events, today: today)
                            legend
                        }
                    }
                    dayList(events, model: model, first: first)
                }
                Text("Tap a row to open it. Pay marks it paid and records the transaction. USD at $1 = Rs 280.")
                    .font(.caption).foregroundStyle(UZColor.label2)
            }
            .padding(.horizontal, UZSpacing.xxl)
            .padding(.bottom, 96)
        }
        .background(UZColor.bg)
        .navigationTitle("Calendar")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Today") {
                    withAnimation(.snappy) { month = nil; selected = nil }
                }
                .accessibilityIdentifier("calendar.today")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Add reminder or event", systemImage: "calendar.badge.plus") { addingEvent = true }
                    .accessibilityIdentifier("calendar.addEvent")
                Button(showsAgenda ? "Month" : "Agenda list", systemImage: showsAgenda ? "calendar" : "list.bullet") {
                    withAnimation(.snappy) { showsAgenda.toggle() }
                }
                .accessibilityIdentifier("calendar.mode")
                NavigationLink(value: Route.bills) {
                    Label("Bills & subscriptions", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("calendar.bills")
            }
        }
        .sheet(item: $paying) { MarkPaidSheet(session: session, occurrence: $0) }
        .sheet(item: $editingEvent) { EventFormSheet(session: session, editing: $0, date: $0.date) }
        .sheet(isPresented: $addingEvent) { EventFormSheet(session: session, editing: nil, date: selected ?? session.today) }
        .onChange(of: session.calendarFocus, initial: true) { _, focus in
            guard let focus else { return }
            month = focus.firstOfMonth
            selected = focus
            showsAgenda = false
            session.calendarFocus = nil
        }
        .accessibilityIdentifier("screen.calendar")
    }

    // MARK: Data

    private func events(from start: LocalDate, through end: LocalDate, model: RecurringModel) -> [CalendarEntry] {
        var result: [CalendarEntry] = []
        for item in session.recurring.items {
            let records = model.records(item)
            for occurrence in OccurrenceGenerator.occurrences(item, records: records, from: start, through: end, today: model.today) {
                result.append(CalendarEntry(id: occurrence.id, date: occurrence.dueDate, kind: kind(item), name: item.name,
                                            meta: meta(item, occurrence, model: model), amount: occurrence.amount,
                                            state: occurrence.state, occurrence: occurrence, route: .recurring(item.id)))
            }
        }
        for loan in session.people.loans where loan.writtenOffAt == nil {
            guard let due = loan.dueDate, due >= start, due <= end, let person = loan.personID else { continue }
            let left = LoanCalculator.outstanding(loan)
            guard left.minorUnits > 0 else { continue }
            let name = session.people.person(person)?.name ?? "Someone"
            result.append(CalendarEntry(id: "loan|\(loan.id)", date: due, kind: .people,
                                        name: loan.direction == .lent ? "\(name) due back" : "Repay \(name)",
                                        meta: loan.direction == .lent ? "Owes you" : "You owe", amount: left,
                                        state: nil, occurrence: nil, route: .person(person)))
        }
        for event in session.events {
            for date in event.dates(from: start, through: end) {
                let time = event.minuteOfDay.map { String(format: "%d:%02d", $0 / 60, $0 % 60) }
                let repeats = event.repeatUnit.map { ["day": "Every day", "week": "Every week", "month": "Every month", "year": "Every year"][$0.rawValue] ?? "" }
                let meta = [time, repeats, event.note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                result.append(CalendarEntry(id: "event|\(event.id)|\(date)", date: date, kind: .event, name: event.title,
                                            meta: meta.isEmpty ? "Reminder" : meta, amount: event.amount ?? .zero(model.base),
                                            state: nil, occurrence: nil, route: nil, custom: event))
            }
        }
        return result.sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
    }

    private func kind(_ item: RecurringItem) -> CalendarEntry.Kind {
        if item.type.isIncome { return .income }
        if item.type.isPlan { return .plan }
        if item.type == .subscription { return .subscription }
        return .bill
    }

    private func meta(_ item: RecurringItem, _ occurrence: Occurrence, model: RecurringModel) -> String {
        if item.type == .installment, let total = item.rule.limit { return "Installment \(occurrence.sequence) of \(total)" }
        if item.type == .kameti, let total = item.rule.limit { return "Contribution \(occurrence.sequence) of \(total)" }
        if let group = session.people.group(item.groupID) {
            return "\(group.name) group · your share \(MoneyFormatter.string(model.myShare(item, occurrence.amount)))"
        }
        if occurrence.state == .overdue { return (item.isEstimated ? "Estimated · " : "") + "was due \(DateText.short(occurrence.scheduledDate))" }
        var parts = [item.type == .subscription ? "Subscription" : item.type.isIncome ? "Income" : item.type.name]
        if let account = session.ledger.account(item.accountID) { parts.append(account.name) }
        return parts.joined(separator: " · ")
    }

    // MARK: Salary card

    @ViewBuilder
    private func salaryCard(_ model: RecurringModel) -> some View {
        if let salary = model.nextSalary, salary.dueDate > model.today {
            let rows = model.due(from: model.today, through: salary.dueDate.addingDays(-1), includeOverdue: true)
                .filter { !$0.item.type.isIncome && !$0.occurrence.isResolved }
            let overdue = rows.filter { $0.occurrence.state == .overdue }
            let days = model.today.days(to: salary.dueDate)
            UZCard {
                VStack(alignment: .leading, spacing: UZSpacing.s) {
                    Text("Due before salary · \(DateText.short(salary.dueDate)) · \(days) \(days == 1 ? "day" : "days")")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(UZColor.label2)
                    AmountText(model.total(rows), font: .system(.title, weight: .bold))
                        .accessibilityIdentifier("calendar.beforeSalary")
                    if !overdue.isEmpty {
                        Label("Includes overdue " + overdue.map { "\($0.item.name.components(separatedBy: " · ").first ?? $0.item.name) "
                                                                    + MoneyFormatter.string(model.baseShare($0.item, $0.occurrence.amount)) }
                                .joined(separator: ", "),
                              systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.semibold)).foregroundStyle(UZColor.negative)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("calendar.salary")
        }
    }

    // MARK: Month grid

    private func monthHeader(_ first: LocalDate) -> some View {
        HStack {
            Button {
                withAnimation(.snappy) { month = first.addingMonths(-1); selected = nil }
            } label: { Image(systemName: "chevron.left").fontWeight(.semibold) }
                .accessibilityLabel("Previous month")
                .accessibilityIdentifier("calendar.previous")
            Spacer()
            Text(first.startDate(in: .current).formatted(.dateTime.month(.wide).year()))
                .font(.headline)
                .accessibilityIdentifier("calendar.month")
            Spacer()
            Button {
                withAnimation(.snappy) { month = first.addingMonths(1); selected = nil }
            } label: { Image(systemName: "chevron.right").fontWeight(.semibold) }
                .accessibilityLabel("Next month")
                .accessibilityIdentifier("calendar.next")
        }
        .padding(.horizontal, UZSpacing.s)
    }

    static let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    /// Grid cell ids: -1…-7 the weekday letters, 100+ the blanks before the 1st, 1…31 the days.
    static func cells(blanks: Int, days: Int) -> [Int] {
        Array((-7 ... -1).reversed()) + (0..<blanks).map { 100 + $0 } + Array(1...days)
    }

    private func grid(_ first: LocalDate, events: [CalendarEntry], today: LocalDate) -> some View {
        let byDay = Dictionary(grouping: events, by: \.date)
        // Monday first: weekday of the 1st (Sun = 1 … Sat = 7) → leading blanks.
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: first.startDate(in: .current))
        let blanks = (weekday + 5) % 7
        let days = LocalDate.daysIn(year: first.year, month: first.month)
        return LazyVGrid(columns: Self.columns, spacing: UZSpacing.xs) {
            // One list with one id per cell: the header, the blanks and the days used to share ids 0…6, and the grid
            // dropped the repeats (that hid the 1st–6th of every month).
            ForEach(Self.cells(blanks: blanks, days: days), id: \.self) { cell in
                if cell < 0 {
                    Text(Self.weekdayLetters[-cell - 1]).font(.caption2.weight(.semibold)).foregroundStyle(UZColor.label2)
                } else if cell >= 100 {
                    Color.clear.frame(height: 44)
                } else {
                    let date = LocalDate(year: first.year, month: first.month, day: cell)
                    dayCell(date, events: byDay[date] ?? [], today: today)
                }
            }
        }
    }

    private func dayCell(_ date: LocalDate, events: [CalendarEntry], today: LocalDate) -> some View {
        let isSelected = selected == date
        let isToday = date == today
        let overdue = events.contains { $0.state == .overdue }
        let allPaid = !events.isEmpty && events.allSatisfy { $0.state == .paid || $0.state == .skipped }
        return Button {
            withAnimation(.snappy) { selected = isSelected ? nil : date }
        } label: {
            VStack(spacing: 2) {
                Text("\(date.day)")
                    .font(.callout.weight(isToday ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white : isToday ? UZColor.tint : UZColor.label)
                    .frame(width: 30, height: 30)
                    .background {
                        if isSelected { Circle().fill(UZColor.tint) } else if isToday { Circle().stroke(UZColor.tint, lineWidth: 1.5) }
                    }
                HStack(spacing: 2) {
                    if overdue {
                        Image(systemName: "exclamationmark").font(.system(size: 8, weight: .black)).foregroundStyle(UZColor.negative)
                    } else if allPaid {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .black)).foregroundStyle(UZColor.positive)
                    } else {
                        ForEach(events.prefix(3)) { event in
                            Image(systemName: event.glyph).font(.system(size: 6)).foregroundStyle(event.color)
                        }
                    }
                }
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility(date, events: events, today: today))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("calendar.day.\(date.day)")
    }

    private func accessibility(_ date: LocalDate, events: [CalendarEntry], today: LocalDate) -> String {
        var text = DateText.short(date) + (date == today ? ", today" : "")
        if events.isEmpty { return text }
        text += ", \(events.count) \(events.count == 1 ? "item" : "items")"
        if events.contains(where: { $0.state == .overdue }) { text += ", overdue" }
        return text
    }

    private var legend: some View {
        let items: [(String, String, Color)] = [("square.fill", "Bill", Color(hex: "#FFCC00")), ("circle.fill", "Subscription", Color(hex: "#FF2D55")),
                                                ("diamond.fill", "Plan", Color(hex: "#00C7BE")), ("triangle.fill", "Income", UZColor.positive),
                                                ("circle", "People", UZColor.tint), ("star.fill", "Reminder", Color(hex: "#AF52DE")), ("checkmark", "Paid", UZColor.positive),
                                                ("exclamationmark", "Overdue", UZColor.negative)]
        return FlowLayout(spacing: UZSpacing.m) {
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: 3) {
                    Image(systemName: items[index].0).font(.system(size: 8, weight: .bold)).foregroundStyle(items[index].2)
                    Text(items[index].1).font(.caption2).foregroundStyle(UZColor.label2)
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Lists

    @ViewBuilder
    private func dayList(_ events: [CalendarEntry], model: RecurringModel, first: LocalDate) -> some View {
        if let selected {
            let rows = events.filter { $0.date == selected }
            group(DateText.short(selected), rows: rows, model: model, empty: "Nothing due this day.")
        } else {
            agenda(events, model: model)
        }
    }

    @ViewBuilder
    private func agenda(_ events: [CalendarEntry], model: RecurringModel) -> some View {
        let today = model.today
        let overdue = events.filter { $0.state == .overdue }
        let open = events.filter { $0.state != .overdue && $0.state != .paid && $0.state != .skipped }
        let done = events.filter { $0.state == .paid || $0.state == .skipped }
        if events.isEmpty {
            UZCard {
                EmptyStateView("Nothing this month", systemImage: "calendar",
                               description: "Bills, subscriptions, installments, loans due back and your own reminders appear on their dates.")
            }
        }
        if !overdue.isEmpty { group("Overdue", rows: overdue, model: model) }
        if !open.isEmpty { group(open.first.map { $0.date >= today } == true ? "Coming up" : "Due", rows: open, model: model) }
        if !done.isEmpty { group("Paid", rows: done, model: model) }
    }

    private func group(_ title: String, rows: [CalendarEntry], model: RecurringModel, empty: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: UZSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title)
                Text("\(rows.count)").font(.subheadline).foregroundStyle(UZColor.label2)
            }
            UZCard(padding: UZSpacing.l) {
                VStack(alignment: .leading, spacing: UZSpacing.l) {
                    if rows.isEmpty, let empty {
                        Text(empty).foregroundStyle(UZColor.label2)
                    }
                    ForEach(rows) { event in row(event, model: model) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.group.\(title)")
    }

    private func row(_ event: CalendarEntry, model: RecurringModel) -> some View {
        HStack(spacing: UZSpacing.m) {
            if let custom = event.custom {
                Button { editingEvent = custom } label: { rowLabel(event, model: model) }
                    .buttonStyle(.plain)
            } else {
                NavigationLink(value: event.route ?? Route.bills) { rowLabel(event, model: model) }
                    .buttonStyle(.plain)
            }
            if let occurrence = event.occurrence, !occurrence.isResolved {
                Button(event.kind == .income ? "Got it" : "Pay") { paying = occurrence }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("calendar.pay.\(event.name)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.row.\(event.name)")
    }

    private func rowLabel(_ event: CalendarEntry, model: RecurringModel) -> some View {
                HStack(spacing: UZSpacing.l) {
                    VStack(spacing: 0) {
                        Text(event.date.startDate(in: .current).formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption2).foregroundStyle(UZColor.label2)
                        Text("\(event.date.day)").font(.headline).monospacedDigit()
                    }
                    .frame(width: 34)
                    Image(systemName: event.glyph).font(.caption).foregroundStyle(event.color).frame(width: 14)
                    VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                        Text(event.name).foregroundStyle(UZColor.label).lineLimit(1)
                        Text(event.meta).font(.footnote).foregroundStyle(UZColor.label2).lineLimit(2)
                    }
                    Spacer(minLength: UZSpacing.s)
                    VStack(alignment: .trailing, spacing: UZSpacing.xxs) {
                        if event.kind != .event || !event.amount.isZero {
                        Text(MoneyFormatter.string(event.amount)).font(.subheadline.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(event.kind == .income ? UZColor.positive : UZColor.label)
                        }
                        if event.amount.currency != model.base {
                            Text(MoneyFormatter.approximate(event.amount, in: model.base, rate: session.ledger.rate(for: event.amount.currency)))
                                .font(.caption).foregroundStyle(UZColor.label2)
                        }
                        if let state = event.state, state != .upcoming { StatusBadge(model.badge(state)) }
                    }
                }
                .contentShape(.rect)
    }
}
