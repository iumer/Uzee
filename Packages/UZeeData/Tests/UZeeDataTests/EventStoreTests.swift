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

    @Test("Plan › To pay: add, pay part, pay the rest, delete")
    func paymentTodos() throws {
        let store = EventStore(database: try AppDatabase.inMemory())
        let kameti = PaymentTodo(name: "Kameti", amount: Money(major: 20_000, .pkr), createdAt: Date(timeIntervalSince1970: 1_790_000_000))
        let fuel = PaymentTodo(name: "Car fuel", amount: Money(major: 40_000, .pkr), createdAt: Date(timeIntervalSince1970: 1_790_000_100))
        try store.save(kameti)
        try store.save(fuel)
        try store.save(try kameti.paying(Money(major: 10_000, .pkr)))
        var list = try store.paymentTodos()
        #expect(list.map(\.name) == ["Kameti", "Car fuel"])
        #expect(list[0].remaining == Money(major: 10_000, .pkr))
        try store.save(try list[0].paying(Money(major: 10_000, .pkr)))
        list = try store.paymentTodos()
        #expect(list.map(\.name) == ["Car fuel", "Kameti"])
        #expect(list[1].isDone)
        try store.deletePaymentTodo(fuel.id)
        #expect(try store.paymentTodos().map(\.name) == ["Kameti"])
        #expect(throws: PaymentTodo.Problem.emptyName) { try store.save(PaymentTodo(name: "", amount: Money(major: 1, .pkr))) }
        let salary = PaymentTodo(direction: .receive, name: "Salary", amount: Money(major: 150_000, .pkr))
        try store.save(salary)
        #expect(try store.paymentTodos().first { $0.id == salary.id }?.direction == .receive)
        #expect(try store.paymentTodos().first { $0.id == kameti.id }?.direction == .pay)
        // Undo of a delete saves it again: it comes back as it was.
        try store.deletePaymentTodo(salary.id)
        #expect(try store.paymentTodos().first { $0.id == salary.id } == nil)
        try store.save(salary)
        #expect(try store.paymentTodos().first { $0.id == salary.id }?.amount == Money(major: 150_000, .pkr))
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
