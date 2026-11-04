// UZee · Built by iUmer Farooq
// Copyright (c) 2026 iUmer Farooq. All rights reserved. See LICENSE.

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
        try store.addTodoPayment(TodoPayment(todoID: kameti.id, amount: Money(major: 10_000, .pkr), paidAt: Date()))
        var list = try store.paymentTodos()
        #expect(list.map(\.name) == ["Kameti", "Car fuel"])
        #expect(list[0].remaining == Money(major: 10_000, .pkr))
        try store.addTodoPayment(TodoPayment(todoID: kameti.id, amount: Money(major: 10_000, .pkr), paidAt: Date()))
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

    @Test("bby (owner, 2026-11-03): paid Rs 4,000 from HBL, fixed to Rs 400,000 in Activity, Cash flow shows Rs 400,000 paid")
    func todoPaymentFollowsActivity() throws {
        let database = try AppDatabase.inMemory()
        let store = EventStore(database: database)
        let ledger = LedgerStore(database: database)
        let hbl = try ledger.createAccount(name: "HBL", kind: .bank, currency: .pkr, openingBalance: Money(major: 1_000_000, .pkr),
                                           openingDate: LocalDate(year: 2026, month: 11, day: 1))
        let bby = PaymentTodo(name: "bby", amount: Money(major: 750_000, .pkr))
        try store.save(bby)
        let txn = MoneyTransaction(kind: .expense, occurredAt: Date(), localDate: LocalDate(year: 2026, month: 11, day: 2), timeZoneID: "Asia/Karachi",
                                   amount: Money(major: 4_000, .pkr), payeeName: "bby",
                                   legs: [TransactionLeg(accountID: hbl.id, amount: Money(major: -4_000, .pkr), role: .main)])
        try ledger.save(txn)
        try store.addTodoPayment(TodoPayment(todoID: bby.id, amount: Money(major: 4_000, .pkr), paidAt: Date(), transactionID: txn.id, accountID: hbl.id))
        #expect(try store.paymentTodos().first?.paid == Money(major: 4_000, .pkr))
        var fixed = txn
        fixed.amount = Money(major: 400_000, .pkr)
        fixed.legs[0].amount = Money(major: -400_000, .pkr)
        try ledger.save(fixed)
        let after = try #require(try store.paymentTodos().first)
        #expect(after.paid == Money(major: 400_000, .pkr))
        #expect(after.remaining == Money(major: 350_000, .pkr))
        #expect(try store.todoPayments(bby.id).map(\.amount) == [Money(major: 400_000, .pkr)])
        // Deleting the entry in Activity drops the payment; restoring it brings it back.
        try ledger.delete(transactionID: txn.id)
        #expect(try store.paymentTodos().first?.paid == Money(major: 0, .pkr))
        try ledger.restore(transactionID: txn.id)
        #expect(try store.paymentTodos().first?.paid == Money(major: 400_000, .pkr))
        // A second, unlinked payment; editing and deleting it.
        let cash = TodoPayment(todoID: bby.id, amount: Money(major: 6_000, .pkr), paidAt: Date())
        try store.addTodoPayment(cash)
        var edited = cash
        edited.amount = Money(major: 60_000, .pkr)
        try store.updateTodoPayment(edited)
        #expect(try store.paymentTodos().first?.paid == Money(major: 460_000, .pkr))
        try store.deleteTodoPayment(cash.id)
        #expect(try store.paymentTodos().first?.paid == Money(major: 400_000, .pkr))
        try store.restoreTodoPayment(cash.id)
        #expect(try store.todoPayments(bby.id).count == 2)
    }

    @Test("Upgrading: what was paid becomes one earlier payment; one matching Activity entry is offered, not linked silently")
    func earlierPaymentsMigrate() throws {
        let database = try AppDatabase.inMemory()
        let store = EventStore(database: database)
        let ledger = LedgerStore(database: database)
        let hbl = try ledger.createAccount(name: "HBL", kind: .bank, currency: .pkr, openingDate: LocalDate(year: 2026, month: 11, day: 1))
        let bby = PaymentTodo(name: "bby", amount: Money(major: 750_000, .pkr), createdAt: Date(timeIntervalSince1970: 1_790_000_000))
        try store.save(bby)
        let txn = MoneyTransaction(kind: .expense, occurredAt: Date(), localDate: LocalDate(year: 2026, month: 11, day: 2), timeZoneID: "Asia/Karachi",
                                   amount: Money(major: 400_000, .pkr), payeeName: "bby",
                                   legs: [TransactionLeg(accountID: hbl.id, amount: Money(major: -400_000, .pkr), role: .main)])
        try ledger.save(txn)
        // As a 0.15.18 phone has it: a stored paid total of Rs 4,000 and no payment rows.
        try database.writer.write { db in
            try db.execute(sql: "UPDATE payment_todo SET paid_minor = 400000")
            try db.execute(sql: "DELETE FROM payment_todo_payment")
            try db.execute(sql: """
                INSERT INTO payment_todo_payment (id, created_at, updated_at, todo_id, amount_minor, currency_code, paid_at, is_earlier)
                SELECT ?, updated_at, updated_at, id, paid_minor, currency_code, updated_at, 1 FROM payment_todo
                """, arguments: [UUID().uuidString])
        }
        #expect(try store.paymentTodos().first?.paid == Money(major: 4_000, .pkr))
        let offer = try #require(try store.suggestedLink(bby.id))
        #expect(offer.amount == Money(major: 400_000, .pkr) && offer.transaction == txn.id)
        try store.linkTodoPayment(offer.payment, transactionID: offer.transaction)
        #expect(try store.paymentTodos().first?.paid == Money(major: 400_000, .pkr))
        #expect(try store.suggestedLink(bby.id) == nil)
    }
}
