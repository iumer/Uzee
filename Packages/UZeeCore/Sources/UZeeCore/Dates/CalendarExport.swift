import Foundation

/// One UZee date written to the iPhone's Calendar (CAL-06): a bill, a custom event or a loan due date.
public struct CalendarExportItem: Hashable, Sendable {
    /// Stable across launches ("bill.<item>.<date>"), so UZee updates or removes only the events it created.
    public var key: String
    public var title: String
    public var date: LocalDate
    /// Minutes after midnight, or nil for an all-day event.
    public var minuteOfDay: Int?
    public var notes: String

    public init(key: String, title: String, date: LocalDate, minuteOfDay: Int? = nil, notes: String) {
        self.key = key
        self.title = title
        self.date = date
        self.minuteOfDay = minuteOfDay
        self.notes = notes
    }
}

/// A calendar on the iPhone that UZee can write to.
public struct CalendarChoice: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let source: String

    public init(id: String, title: String, source: String) {
        self.id = id
        self.title = title
        self.source = source
    }
}

/// What should be in the Calendar right now: upcoming bills, events and loans for the next two months.
public enum CalendarExportPlanner {
    public static let horizonDays = 62

    public static func items(recurring: RecurringSnapshot, events: [CalendarEvent],
                             loans: [(name: String, outstanding: Money, due: LocalDate, owedToMe: Bool)],
                             hideAmounts: Bool, today: LocalDate, format: (Money) -> String) -> [CalendarExportItem] {
        let through = today.addingDays(horizonDays)
        var items: [CalendarExportItem] = []
        for item in recurring.items where item.isActive {
            let occurrences = OccurrenceGenerator.occurrences(item, records: recurring.records(for: item.id), from: today,
                                                             through: through, today: today)
            for occurrence in occurrences where !occurrence.isResolved {
                let amount = hideAmounts ? "" : " · \(format(occurrence.amount))"
                items.append(CalendarExportItem(
                    key: "bill.\(item.id.uuidString).\(occurrence.scheduledDate)",
                    title: (item.type.isIncome ? "\(item.name) expected" : "\(item.name) due") + amount,
                    date: occurrence.dueDate, notes: "From UZee. Mark it paid in UZee."))
            }
        }
        for event in events {
            for date in event.dates(from: today, through: through) {
                let amount = event.amount.map { hideAmounts ? "" : " · \(format($0))" } ?? ""
                items.append(CalendarExportItem(key: "event.\(event.id.uuidString).\(date)", title: event.title + amount, date: date,
                                                minuteOfDay: event.minuteOfDay, notes: event.note ?? "From UZee."))
            }
        }
        for loan in loans where loan.due >= today && loan.due <= through {
            let amount = hideAmounts ? "" : " · \(format(loan.outstanding))"
            items.append(CalendarExportItem(
                key: "loan.\(loan.name).\(loan.due)",
                title: (loan.owedToMe ? "\(loan.name) pays you back" : "Pay \(loan.name) back") + amount,
                date: loan.due, notes: "From UZee."))
        }
        return items.sorted { ($0.date, $0.key) < ($1.date, $1.key) }
    }

    /// What to do with the Calendar, given the events UZee made before (key → event id).
    public struct Changes: Equatable, Sendable {
        public var create: [CalendarExportItem]
        public var update: [(id: String, item: CalendarExportItem)]
        public var delete: [String]

        public static func == (a: Changes, b: Changes) -> Bool {
            a.create == b.create && a.delete == b.delete
                && a.update.map(\.id) == b.update.map(\.id) && a.update.map(\.item) == b.update.map(\.item)
        }
    }

    /// Past events stay as a record; only UZee's future ones that no longer apply are removed.
    public static func changes(wanted: [CalendarExportItem], existing: [String: String], existingDates: [String: LocalDate],
                               today: LocalDate) -> Changes {
        let wantedKeys = Set(wanted.map(\.key))
        var create: [CalendarExportItem] = []
        var update: [(id: String, item: CalendarExportItem)] = []
        for item in wanted {
            if let id = existing[item.key] { update.append((id, item)) } else { create.append(item) }
        }
        let delete = existing.filter { key, _ in !wantedKeys.contains(key) && (existingDates[key].map { $0 >= today } ?? true) }
            .map(\.value).sorted()
        return Changes(create: create, update: update, delete: delete)
    }
}
