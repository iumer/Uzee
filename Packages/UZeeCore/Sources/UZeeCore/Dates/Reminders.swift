import Foundation

/// A custom calendar entry (CAL-03): a payment to remember that isn't a bill, or anything else
/// ("Car tuning", "Ammi's birthday"), optionally repeating, optionally with an amount and a reminder.
public struct CalendarEvent: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    /// First (or only) date; repeats follow `repeatUnit` from here.
    public var date: LocalDate
    /// Minutes after midnight, or nil for all day.
    public var minuteOfDay: Int?
    public var repeatUnit: RecurrenceUnit?
    public var amount: Money?
    public var note: String?
    /// Days before to remind; nil uses the global default, -1 means no reminder.
    public var remindDaysBefore: Int?
    public var isSample: Bool

    public init(id: UUID = UUID(), title: String, date: LocalDate, minuteOfDay: Int? = nil, repeatUnit: RecurrenceUnit? = nil,
                amount: Money? = nil, note: String? = nil, remindDaysBefore: Int? = nil, isSample: Bool = false) {
        self.id = id
        self.title = title
        self.date = date
        self.minuteOfDay = minuteOfDay
        self.repeatUnit = repeatUnit
        self.amount = amount
        self.note = note
        self.remindDaysBefore = remindDaysBefore
        self.isSample = isSample
    }

    public enum Problem: Error, Equatable, Sendable { case emptyTitle, invalidAmount }

    public func validate() throws(Problem) {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { throw .emptyTitle }
        if let amount, amount.minorUnits <= 0 { throw .invalidAmount }
    }

    /// Dates in `from...through`.
    public func dates(from: LocalDate, through: LocalDate) -> [LocalDate] {
        guard let unit = repeatUnit else { return (from...through).contains(date) ? [date] : [] }
        return RecurrenceRule(unit: unit, interval: 1, anchor: date).occurrences(from: from, through: through).map(\.date)
    }

    public var wantsReminder: Bool { remindDaysBefore != -1 }
}

/// Global reminder preferences (CAL-04): default 1 day before at 10:00.
public struct ReminderSettings: Hashable, Sendable, Codable {
    public var isOn: Bool
    public var daysBefore: Int
    public var minuteOfDay: Int
    /// "Netflix due tomorrow" without the amount, for a lock screen others can see.
    public var hideAmounts: Bool

    public init(isOn: Bool = true, daysBefore: Int = 1, minuteOfDay: Int = 10 * 60, hideAmounts: Bool = false) {
        self.isOn = isOn
        self.daysBefore = daysBefore
        self.minuteOfDay = minuteOfDay
        self.hideAmounts = hideAmounts
    }

    public static let standard = ReminderSettings()
}

/// One local notification to schedule.
public struct PlannedReminder: Hashable, Sendable {
    public enum Kind: String, Sendable { case bill, event, loan }

    /// Stable, so rescheduling replaces rather than duplicates: "uzee.bill.<item>.<date>".
    public var id: String
    public var kind: Kind
    public var fireDate: LocalDate
    public var minuteOfDay: Int
    public var title: String
    public var body: String
    /// For bills: the item and scheduled date that Mark paid and Snooze act on.
    public var itemID: UUID?
    public var scheduledDate: LocalDate?

    public static let idPrefix = "uzee."
}

/// Plans one reminder per upcoming occurrence (CAL-05), nearest first, never more than iOS allows (64 pending;
/// UZee keeps a margin). A reminder whose lead time has passed falls back to the morning of the due day;
/// if that has passed too, there's no reminder, so nothing nags.
public enum ReminderPlanner {
    public static let cap = 60
    /// How far ahead to look; later reminders are added as time passes (on launch and on every change).
    public static let horizonDays = 62

    public static func plan(recurring: RecurringSnapshot, events: [CalendarEvent], loans: [(name: String, outstanding: Money, due: LocalDate, owedToMe: Bool)],
                            settings: ReminderSettings, today: LocalDate, minuteNow: Int,
                            format: (Money) -> String) -> [PlannedReminder] {
        guard settings.isOn else { return [] }
        let through = today.addingDays(horizonDays)
        var planned: [PlannedReminder] = []

        func when(due: LocalDate, daysBefore: Int, minute: Int) -> (LocalDate, Int)? {
            let lead = due.addingDays(-max(0, daysBefore))
            if lead > today || (lead == today && minute > minuteNow) { return (lead, minute) }
            if due > today || (due == today && minute > minuteNow) { return (due, minute) }
            return nil
        }

        func phrase(_ due: LocalDate, from fire: LocalDate) -> String {
            switch fire.days(to: due) {
            case 0: "today"
            case 1: "tomorrow"
            case let n: "in \(n) days"
            }
        }

        for item in recurring.items where item.isActive && !item.type.isIncome {
            let occurrences = OccurrenceGenerator.occurrences(item, records: recurring.records(for: item.id), from: today,
                                                             through: through, today: today)
            for occurrence in occurrences where !occurrence.isResolved {
                guard let (fire, minute) = when(due: occurrence.dueDate, daysBefore: settings.daysBefore, minute: settings.minuteOfDay)
                else { continue }
                let amount = settings.hideAmounts ? "" : "\(format(occurrence.amount)) · "
                planned.append(PlannedReminder(
                    id: "\(PlannedReminder.idPrefix)bill.\(item.id.uuidString).\(occurrence.scheduledDate)", kind: .bill,
                    fireDate: fire, minuteOfDay: minute, title: "\(item.name) due \(phrase(occurrence.dueDate, from: fire))",
                    body: "\(amount)Mark it paid or snooze it from here.", itemID: item.id, scheduledDate: occurrence.scheduledDate))
            }
        }

        for event in events where event.wantsReminder {
            for date in event.dates(from: today, through: through) {
                let minute = event.minuteOfDay ?? settings.minuteOfDay
                guard let (fire, at) = when(due: date, daysBefore: event.remindDaysBefore ?? settings.daysBefore, minute: minute)
                else { continue }
                let amount = event.amount.map { settings.hideAmounts ? "" : format($0) } ?? ""
                let body = [amount, event.note ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                planned.append(PlannedReminder(
                    id: "\(PlannedReminder.idPrefix)event.\(event.id.uuidString).\(date)", kind: .event, fireDate: fire, minuteOfDay: at,
                    title: fire == date ? event.title : "\(event.title) \(phrase(date, from: fire))",
                    body: body.isEmpty ? "From your UZee calendar." : body, itemID: event.id, scheduledDate: date))
            }
        }

        for loan in loans where loan.due >= today && loan.due <= through {
            guard let (fire, minute) = when(due: loan.due, daysBefore: settings.daysBefore, minute: settings.minuteOfDay) else { continue }
            let amount = settings.hideAmounts ? "" : " \(format(loan.outstanding))"
            planned.append(PlannedReminder(
                id: "\(PlannedReminder.idPrefix)loan.\(loan.name).\(loan.due)", kind: .loan, fireDate: fire, minuteOfDay: minute,
                title: loan.owedToMe ? "\(loan.name) should pay you back \(phrase(loan.due, from: fire))"
                                     : "Pay \(loan.name) back \(phrase(loan.due, from: fire))",
                body: loan.owedToMe ? "\(loan.name) owes you\(amount)." : "You owe\(amount).", itemID: nil, scheduledDate: loan.due))
        }

        return Array(planned.sorted { ($0.fireDate, $0.minuteOfDay, $0.id) < ($1.fireDate, $1.minuteOfDay, $1.id) }.prefix(cap))
    }
}
