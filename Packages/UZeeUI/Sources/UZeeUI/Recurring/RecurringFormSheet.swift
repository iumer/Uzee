import SwiftUI
import UZeeCore

/// New or edit recurring (SCR-19, REC-01/03): name, amount, type, how often, first due date, account,
/// category, optional group split, and for plans the number of payments and how many are already paid.
/// A new amount applies from the next due date and is added to price history.
struct RecurringFormSheet: View {
    @Bindable var session: AppSession
    let item: RecurringItem?
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var amountText = ""
    @State private var currency: Currency = .pkr
    @State private var type: RecurringType = .bill
    @State private var unit: RecurrenceUnit = .month
    @State private var interval = 1
    @State private var firstDue = Date()
    @State private var hasEnd = false
    @State private var endDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var count = 12
    @State private var paidBefore = 0
    @State private var accountID: UUID?
    @State private var categoryID: UUID?
    @State private var groupID: UUID?
    @State private var isEstimated = false
    @State private var colorHex = "#FF2D55"
    @State private var notes = ""
    @State private var problem: String?
    @State private var didLoad = false

    static let colors: [(String, String)] = [("Pink", "#FF2D55"), ("Indigo", "#5856D6"), ("Orange", "#FF9500"), ("Teal", "#30B0C7"),
                                             ("Green", "#34C759"), ("Blue", "#007AFF"), ("Yellow", "#FFCC00"), ("Graphite", "#8E8E93")]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("recurringForm.name")
                    HStack {
                        Menu {
                            ForEach(currencies, id: \.code) { option in
                                Button(option.code) { currency = option }
                            }
                        } label: {
                            Text(currency.symbol).font(.title2.bold()).foregroundStyle(UZColor.label2)
                        }
                        TextField("0", text: $amountText)
                            .font(.title2.bold())
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                            .accessibilityIdentifier("recurringForm.amount")
                    }
                    Toggle("Amount varies (estimate)", isOn: $isEstimated)
                }
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(RecurringType.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .accessibilityIdentifier("recurringForm.type")
                    Picker("Repeats", selection: $unit) {
                        Text("Weekly").tag(RecurrenceUnit.week)
                        Text("Monthly").tag(RecurrenceUnit.month)
                        Text("Yearly").tag(RecurrenceUnit.year)
                        Text("Daily").tag(RecurrenceUnit.day)
                    }
                    Stepper("Every \(interval) \(unitName(interval))", value: $interval, in: 1...12)
                    DatePicker(type.isPlan ? "First payment" : "Next due", selection: $firstDue, displayedComponents: .date)
                    if type.isPlan {
                        Stepper("\(count) payments in total", value: $count, in: 1...360)
                        Stepper("\(paidBefore) already paid", value: $paidBefore, in: 0...max(0, count - 1))
                    } else {
                        Toggle("End date", isOn: $hasEnd)
                        if hasEnd { DatePicker("Ends", selection: $endDate, displayedComponents: .date) }
                    }
                } footer: {
                    Text(type.isPlan ? "Payments already made before UZee are counted, never shown as due."
                                     : "Leave End date off if it keeps going.")
                }
                Section {
                    Picker(type.isIncome ? "Goes to" : "Pays from", selection: $accountID) {
                        Text("Choose when paid").tag(UUID?.none)
                        ForEach(session.ledger.activeAccounts) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    NavigationLink {
                        CategoryPicker(categories: session.ledger.categories, type: type.isIncome ? .income : .expense, selection: $categoryID)
                    } label: {
                        LabeledContent("Category", value: session.ledger.categoryPath(categoryID) ?? "Choose")
                    }
                    Picker("Split with", selection: $groupID) {
                        Text("No one").tag(UUID?.none)
                        ForEach(session.people.groups.filter { $0.archivedAt == nil }) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                } footer: {
                    Text("Split bills count only your share toward your budget. Estimated amounts can be corrected when you mark them paid.")
                }
                Section("Look") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: UZSpacing.m) {
                            ForEach(Self.colors.indices, id: \.self) { index in
                                let (label, hex) = Self.colors[index]
                                Button {
                                    colorHex = hex
                                } label: {
                                    Circle().fill(Color(hex: hex)).frame(width: 30, height: 30)
                                        .overlay { if colorHex == hex { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(label)
                                .accessibilityAddTraits(colorHex == hex ? .isSelected : [])
                            }
                        }
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                if let problem {
                    Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(UZColor.negative) }
                }
            }
            .navigationTitle(item == nil ? "New recurring" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold).accessibilityIdentifier("recurringForm.save")
                }
            }
            .onAppear(perform: load)
        }
    }

    private var currencies: [Currency] {
        var seen: [Currency] = [session.ledger.base]
        for account in session.ledger.activeAccounts where !seen.contains(account.currency) { seen.append(account.currency) }
        return seen
    }

    private func unitName(_ n: Int) -> String {
        let word: String
        switch unit {
        case .day: word = "day"
        case .week: word = "week"
        case .month: word = "month"
        case .year: word = "year"
        }
        return n == 1 ? word : word + "s"
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        currency = session.ledger.base
        guard let item else { return }
        name = item.name
        amountText = MarkPaidSheet.plain(item.amount)
        currency = item.amount.currency
        type = item.type
        unit = item.rule.unit
        interval = item.rule.interval
        isEstimated = item.isEstimated
        accountID = item.accountID
        categoryID = item.categoryID
        groupID = item.groupID
        colorHex = item.colorHex
        notes = item.notes ?? ""
        count = item.rule.limit ?? 12
        paidBefore = item.paidBeforeTracking
        if let end = item.rule.end {
            hasEnd = true
            endDate = end.startDate(in: .current)
        }
        // Edit shows the next due date for regular items, the first payment for plans.
        let next = RecurringModel(session: session).next(item)?.scheduledDate
        firstDue = (item.type.isPlan ? item.rule.anchor : next ?? item.rule.anchor).startDate(in: .current)
    }

    private func save() {
        let money: Money
        do {
            money = try AmountParser.parse(amountText, currency: currency)
        } catch {
            problem = "Add a name and an amount."
            return
        }
        let first = LocalDate(firstDue, in: .current)
        var anchor = first
        // Editing a regular item keeps its anchor day unless the date moved off the schedule.
        if let item, !type.isPlan, item.rule.unit == unit, item.rule.interval == interval,
           item.rule.date(at: item.rule.firstIndex(onOrAfter: first)) == first {
            anchor = item.rule.anchor
        }
        let rule = RecurrenceRule(unit: unit, interval: interval, anchor: anchor,
                                  end: !type.isPlan && hasEnd ? LocalDate(endDate, in: .current) : nil,
                                  limit: type.isPlan ? count : nil)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = item ?? RecurringItem(name: name, type: type, amount: money, rule: rule, trackedFrom: type.isPlan ? session.today : first,
                                            startedOn: first)
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.type = type
        updated.amount = money
        updated.isEstimated = isEstimated
        updated.accountID = accountID
        updated.categoryID = categoryID
        updated.groupID = groupID
        updated.rule = rule
        updated.paidBeforeTracking = type.isPlan ? min(paidBefore, count) : 0
        updated.colorHex = colorHex
        updated.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        if item == nil && type.isPlan { updated.trackedFrom = rule.date(at: min(paidBefore, count - 1)) ?? first }
        do {
            try updated.validate()
        } catch let failure as RecurringItem.Problem {
            problem = failure == .invalidRule ? "Check how often it repeats and the end date." : "Add a name and an amount."
            return
        } catch {
            problem = "Add a name and an amount."
            return
        }
        let priceFrom = item.flatMap { RecurringModel(session: session).next($0)?.scheduledDate } ?? first
        if session.perform("Couldn't save. Nothing was changed. Try again.", { try session.recurringClient.save(updated, priceFrom) }) {
            session.toasts.show(item == nil ? "Added \(updated.name)" : "Changes saved")
            // The first bill is when reminders start to matter: ask for notifications once.
            if item == nil { Task { _ = await session.calendar.requestNotifications(); session.rescheduleReminders() } }
            dismiss()
        }
    }
}
