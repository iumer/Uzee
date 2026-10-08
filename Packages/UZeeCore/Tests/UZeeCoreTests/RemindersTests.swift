import Foundation
import Testing
@testable import UZeeCore

/// M7 reminders (CAL-03…05): one reminder per occurrence at the right local time, capped, no nagging.
@Suite("Reminders")
struct RemindersTests {
    let today = LocalDate(year: 2026, month: 10, day: 8)
    func rs(_ major: Int64) -> Money { Money(major: major, .pkr) }
    func format(_ money: Money) -> String { MoneyFormatter.string(money) }

    func netflix(anchor: LocalDate) -> RecurringItem {
        RecurringItem(name: "Netflix", type: .subscription, amount: rs(1_100), rule: RecurrenceRule(unit: .month, anchor: anchor))
    }

    @Test("CAL-004 a day before at 10:00; amounts hidden on request; paid occurrences get none")
    func billReminders() {
        let item = netflix(anchor: LocalDate(year: 2026, month: 10, day: 12))
        let paidNov = OccurrenceRecord(itemID: item.id, scheduledDate: LocalDate(year: 2026, month: 11, day: 12), status: .paid)
        let snapshot = RecurringSnapshot(items: [item], records: [paidNov])
        let plan = ReminderPlanner.plan(recurring: snapshot, events: [], loans: [], settings: .standard, today: today, minuteNow: 9 * 60,
                                        format: format)
        #expect(plan.count == 1)  // November is paid; December is past the horizon
        #expect(plan[0].fireDate == LocalDate(year: 2026, month: 10, day: 11))
        #expect(plan[0].minuteOfDay == 600)
        #expect(plan[0].title == "Netflix due tomorrow")
        #expect(plan[0].body.contains("1,100"))
        #expect(plan[0].scheduledDate == LocalDate(year: 2026, month: 10, day: 12))
        var hidden = ReminderSettings.standard
        hidden.hideAmounts = true
        let quiet = ReminderPlanner.plan(recurring: snapshot, events: [], loans: [], settings: hidden, today: today, minuteNow: 0, format: format)
        #expect(!quiet[0].body.contains("1,100"))
        var off = ReminderSettings.standard
        off.isOn = false
        #expect(ReminderPlanner.plan(recurring: snapshot, events: [], loans: [], settings: off, today: today, minuteNow: 0, format: format).isEmpty)
    }

    @Test("CAL-005 a missed lead time falls back to the due morning; a missed due time gets nothing")
    func noNagging() {
        let tomorrow = netflix(anchor: today.addingDays(1))
        let todayItem = netflix(anchor: today)
        let snapshot = RecurringSnapshot(items: [tomorrow, todayItem], records: [])
        let plan = ReminderPlanner.plan(recurring: snapshot, events: [], loans: [], settings: .standard, today: today, minuteNow: 15 * 60,
                                        format: format).filter { $0.fireDate < today.addingDays(20) }
        #expect(plan.count == 1)
        #expect(plan[0].fireDate == today.addingDays(1))
        #expect(plan[0].title == "Netflix due today")
    }

    @Test("CAL-003 events: own time, repeats, no-reminder option; loans due")
    func eventsAndLoans() {
        let birthday = CalendarEvent(title: "Ammi's birthday", date: LocalDate(year: 2026, month: 10, day: 20), minuteOfDay: 9 * 60,
                                     repeatUnit: .year, remindDaysBefore: 0)
        let silent = CalendarEvent(title: "Quiet", date: today.addingDays(3), remindDaysBefore: -1)
        let tuning = CalendarEvent(title: "Car tuning", date: today.addingDays(2), amount: rs(6_500))
        let plan = ReminderPlanner.plan(recurring: .empty, events: [birthday, silent, tuning],
                                        loans: [(name: "Usama", outstanding: rs(25_000), due: today.addingDays(5), owedToMe: true)],
                                        settings: .standard, today: today, minuteNow: 0, format: format)
        #expect(plan.map(\.title) == ["Car tuning tomorrow", "Usama should pay you back tomorrow", "Ammi's birthday"])
        #expect(plan[0].body.contains("6,500"))
        #expect(plan[2].minuteOfDay == 540)
    }

    @Test("CAL-018 never more than the cap, nearest first")
    func cap() {
        let daily = CalendarEvent(title: "Daily", date: today.addingDays(1), repeatUnit: .day)
        let plan = ReminderPlanner.plan(recurring: .empty, events: [daily], loans: [], settings: .standard, today: today, minuteNow: 0,
                                        format: format)
        #expect(plan.count == ReminderPlanner.cap)
        #expect(plan.first?.fireDate == today)
        #expect(zip(plan, plan.dropFirst()).allSatisfy { $0.fireDate <= $1.fireDate })
    }
}

@Suite("Apple Calendar export")
struct CalendarExportTests {
    let today = LocalDate(year: 2026, month: 10, day: 8)

    @Test("Creates new, updates known, removes only UZee's future events that no longer apply")
    func changes() {
        let a = CalendarExportItem(key: "bill.a", title: "Rent due", date: LocalDate(year: 2026, month: 10, day: 10), notes: "")
        let b = CalendarExportItem(key: "event.b", title: "Car tuning", date: LocalDate(year: 2026, month: 10, day: 20), notes: "")
        let existing = ["bill.a": "id-a", "bill.old": "id-old", "bill.past": "id-past"]
        let dates = ["bill.a": LocalDate(year: 2026, month: 10, day: 10), "bill.old": LocalDate(year: 2026, month: 10, day: 12),
                     "bill.past": LocalDate(year: 2026, month: 9, day: 1)]
        let changes = CalendarExportPlanner.changes(wanted: [a, b], existing: existing, existingDates: dates, today: today)
        #expect(changes.create == [b])
        #expect(changes.update.map(\.id) == ["id-a"])
        #expect(changes.delete == ["id-old"])
    }

    @Test("Custom events in range become calendar items")
    func items() {
        let event = CalendarEvent(title: "Ammi's birthday", date: LocalDate(year: 2026, month: 10, day: 15))
        let items = CalendarExportPlanner.items(recurring: .empty, events: [event], loans: [], hideAmounts: false, today: today,
                                                format: { "\($0.minorUnits)" })
        #expect(items.map(\.title) == ["Ammi's birthday"])
        #expect(items.first?.key == "event.\(event.id.uuidString).2026-10-15")
    }
}
