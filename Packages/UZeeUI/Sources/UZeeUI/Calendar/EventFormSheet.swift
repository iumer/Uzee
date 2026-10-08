import SwiftUI
import UZeeCore

/// Add or edit your own reminder or event (CAL-03): a title, a day, an optional time, repeat and amount,
/// and when to be reminded.
struct EventFormSheet: View {
    @Bindable var session: AppSession
    let editing: UZeeCore.CalendarEvent?
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var day = Date()
    @State private var hasTime = false
    @State private var time = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var repeatUnit: RecurrenceUnit?
    @State private var amount = ""
    @State private var note = ""
    /// nil = default, -1 = none, otherwise days before.
    @State private var remind: Int?
    @State private var problem: String?
    @State private var confirmDelete = false

    init(session: AppSession, editing: UZeeCore.CalendarEvent?, date: LocalDate) {
        self.session = session
        self.editing = editing
        let start = editing?.date ?? date
        _day = State(initialValue: start.startDate(in: .current))
        _title = State(initialValue: editing?.title ?? "")
        _repeatUnit = State(initialValue: editing?.repeatUnit)
        _note = State(initialValue: editing?.note ?? "")
        _remind = State(initialValue: editing?.remindDaysBefore)
        if let minute = editing?.minuteOfDay {
            _hasTime = State(initialValue: true)
            _time = State(initialValue: Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date())
        }
        if let money = editing?.amount { _amount = State(initialValue: AmountTyping.grouped("\(money.decimalValue)")) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What, e.g. Car tuning", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("event.title")
                    DatePicker("Date", selection: $day, displayedComponents: .date)
                    Toggle("At a time", isOn: $hasTime.animation())
                    if hasTime {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    }
                    Picker("Repeat", selection: $repeatUnit) {
                        Text("Never").tag(RecurrenceUnit?.none)
                        Text("Every day").tag(RecurrenceUnit?.some(.day))
                        Text("Every week").tag(RecurrenceUnit?.some(.week))
                        Text("Every month").tag(RecurrenceUnit?.some(.month))
                        Text("Every year").tag(RecurrenceUnit?.some(.year))
                    }
                }
                Section {
                    TextField("Amount (optional)", text: $amount)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                        .onChange(of: amount) { _, text in
                            let grouped = AmountTyping.grouped(text)
                            if grouped != text { amount = grouped }
                        }
                        .accessibilityIdentifier("event.amount")
                    TextField("Note", text: $note, axis: .vertical)
                } footer: {
                    Text("An amount here is only a reminder. To track a regular bill with payments, add it in Bills & subscriptions.")
                }
                Section("Remind me") {
                    Picker("Remind me", selection: $remind) {
                        Text("Default (\(Self.leadText(session.reminderSettings.daysBefore)))").tag(Int?.none)
                        Text("On the day").tag(Int?.some(0))
                        Text("1 day before").tag(Int?.some(1))
                        Text("2 days before").tag(Int?.some(2))
                        Text("1 week before").tag(Int?.some(7))
                        Text("Don't remind").tag(Int?.some(-1))
                    }
                    .labelsHidden()
                    .pickerStyle(.inline)
                }
                if let problem {
                    Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(UZColor.negative) }
                }
                if editing != nil {
                    Section {
                        Button("Delete", role: .destructive) { confirmDelete = true }
                            .accessibilityIdentifier("event.delete")
                    }
                }
            }
            .navigationTitle(editing == nil ? "New reminder" : "Edit reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("event.save")
                }
            }
            .confirmationDialog("Delete this reminder?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let editing { session.deleteEvent(editing.id) }
                    dismiss()
                }
            }
        }
    }

    static func leadText(_ days: Int) -> String {
        switch days {
        case 0: "on the day"
        case 1: "1 day before"
        case 7: "1 week before"
        default: "\(days) days before"
        }
    }

    private func save() {
        var money: Money?
        let text = amount.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        if !text.isEmpty {
            guard let parsed = try? AmountParser.parse(text, currency: session.ledger.base), parsed.minorUnits > 0 else {
                problem = "Enter the amount as a number, or leave it empty."
                return
            }
            money = parsed
        }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let event = UZeeCore.CalendarEvent(id: editing?.id ?? UUID(), title: title, date: LocalDate(day, in: .current),
                                           minuteOfDay: hasTime ? (parts.hour ?? 0) * 60 + (parts.minute ?? 0) : nil,
                                           repeatUnit: repeatUnit, amount: money, note: note, remindDaysBefore: remind,
                                           isSample: editing?.isSample ?? false)
        if session.saveEvent(event) {
            session.toasts.show(editing == nil ? "Reminder added" : "Reminder saved")
            dismiss()
        }
    }
}

/// Settings › Reminders (CAL-04): default lead time and time of day, hiding amounts, and notification permission.
struct ReminderSettingsView: View {
    @Bindable var session: AppSession
    @State private var allowed: Bool?

    var body: some View {
        let settings = session.reminderSettings
        Form {
            Section {
                Toggle("Reminders", isOn: binding(\.isOn))
                    .accessibilityIdentifier("reminders.on")
                if settings.isOn {
                    Picker("Remind me", selection: binding(\.daysBefore)) {
                        ForEach([0, 1, 2, 3, 7], id: \.self) { Text(EventFormSheet.leadText($0).capitalizedFirst).tag($0) }
                    }
                    DatePicker("At", selection: timeBinding, displayedComponents: .hourAndMinute)
                    Toggle("Hide amounts", isOn: binding(\.hideAmounts))
                }
            } footer: {
                Text("One reminder for each bill, subscription, installment, loan due back and your own reminders. From the notification you can mark a bill paid or snooze it a day. Times follow the time zone you are in.")
            }
            if allowed == false {
                Section {
                    Button("Allow notifications") {
                        Task {
                            allowed = await session.calendar.requestNotifications()
                            if allowed == false, let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                await UIApplication.shared.open(url)
                            }
                            session.rescheduleReminders()
                        }
                    }
                    .accessibilityIdentifier("reminders.allow")
                } footer: {
                    Text("Notifications are off for UZee. The Calendar still shows everything that's due.")
                }
            }
        }
        .navigationTitle("Reminders")
        .task { allowed = await session.calendar.notificationsAllowed() }
    }

    private func binding<Value>(_ path: WritableKeyPath<ReminderSettings, Value>) -> Binding<Value> {
        Binding(get: { session.reminderSettings[keyPath: path] }, set: { value in
            var settings = session.reminderSettings
            settings[keyPath: path] = value
            session.setReminderSettings(settings)
        })
    }

    private var timeBinding: Binding<Date> {
        Binding(get: {
            let minute = session.reminderSettings.minuteOfDay
            return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            var settings = session.reminderSettings
            settings.minuteOfDay = (parts.hour ?? 10) * 60 + (parts.minute ?? 0)
            session.setReminderSettings(settings)
        })
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
