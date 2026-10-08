import Foundation
import Testing
import UZeeCore
@testable import UZeeData

/// CAL-03/04 integration: custom events round-trip, edit, delete; reminder settings persist.
@Suite("Event store")
struct EventStoreTests {
    @Test("CAL-003 save, edit and delete an event with amount, time and repeat")
    func events() throws {
        let store = EventStore(database: try AppDatabase.inMemory())
        var event = CalendarEvent(title: "Car tuning", date: LocalDate(year: 2026, month: 10, day: 20), minuteOfDay: 17 * 60,
                                  repeatUnit: .month, amount: Money(major: 6_500, .pkr), note: "Toyota Motors", remindDaysBefore: 2)
        try store.save(event)
        #expect(try store.events() == [event])
        event.title = "Car service"
        event.amount = nil
        try store.save(event)
        #expect(try store.events().map(\.title) == ["Car service"])
        #expect(try store.events().first?.amount == nil)
        try store.delete(event.id)
        #expect(try store.events().isEmpty)
        #expect(throws: CalendarEvent.Problem.emptyTitle) { try store.save(CalendarEvent(title: " ", date: event.date)) }
    }

    @Test("CAL-004 reminder settings default to a day before at 10:00 and persist")
    func settings() throws {
        let store = EventStore(database: try AppDatabase.inMemory())
        #expect(try store.reminderSettings() == .standard)
        let custom = ReminderSettings(isOn: true, daysBefore: 2, minuteOfDay: 9 * 60 + 30, hideAmounts: true)
        try store.setReminderSettings(custom)
        try store.setReminderSettings(custom)
        #expect(try store.reminderSettings() == custom)
    }
}
