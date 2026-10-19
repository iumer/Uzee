import Foundation
import Testing
@testable import UZeeCore

@Suite("Paid early: dates count from the payment")
struct PaidEarlyTests {
    func day(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d) }

    @Test("Monthly on the 20th, paid on the 19th: next is the 19th of next month; earlier dates unchanged")
    func monthly() throws {
        let rule = RecurrenceRule(unit: .month, anchor: day(2026, 1, 20))
        let moved = try #require(rule.restarting(at: 9, on: day(2026, 10, 19)))
        #expect(moved.date(at: 8) == day(2026, 9, 20))
        #expect(moved.date(at: 9) == day(2026, 10, 19))
        #expect(moved.date(at: 10) == day(2026, 11, 19))
        #expect(moved.firstIndex(onOrAfter: day(2026, 10, 20)) == 10)
        #expect(moved.firstIndex(onOrAfter: day(2026, 9, 21)) == 9)
        #expect(moved.occurrences(from: day(2026, 9, 1), through: day(2026, 12, 31)).map(\.date)
                == [day(2026, 9, 20), day(2026, 10, 19), day(2026, 11, 19), day(2026, 12, 19)])
    }

    @Test("Paid early twice: each move counts from its own payment")
    func twice() throws {
        let rule = RecurrenceRule(unit: .month, anchor: day(2026, 1, 20))
        let first = try #require(rule.restarting(at: 9, on: day(2026, 10, 19)))
        let second = try #require(first.restarting(at: 10, on: day(2026, 11, 15)))
        #expect(second.date(at: 9) == day(2026, 10, 19))
        #expect(second.date(at: 10) == day(2026, 11, 15))
        #expect(second.date(at: 11) == day(2026, 12, 15))
        #expect(RecurrenceRule.restarts(from: second.restartsText) == second.restarts)
    }

    @Test("Every 30 days, a 31st-of-month bill, a yearly item and an installment with a limit")
    func kinds() throws {
        let days = RecurrenceRule(unit: .day, interval: 30, anchor: day(2026, 9, 20))
        #expect(try #require(days.restarting(at: 1, on: day(2026, 10, 18))).date(at: 2) == day(2026, 11, 17))
        let month31 = RecurrenceRule(unit: .month, anchor: day(2026, 1, 31))
        let moved31 = try #require(month31.restarting(at: 9, on: day(2026, 10, 30)))
        #expect(moved31.date(at: 8) == day(2026, 9, 30))
        #expect(moved31.date(at: 10) == day(2026, 11, 30))
        let yearly = RecurrenceRule(unit: .year, anchor: day(2024, 3, 1))
        #expect(try #require(yearly.restarting(at: 2, on: day(2026, 2, 20))).date(at: 3) == day(2027, 2, 20))
        let plan = RecurrenceRule(unit: .month, anchor: day(2026, 1, 10), limit: 12)
        let movedPlan = try #require(plan.restarting(at: 9, on: day(2026, 10, 5)))
        #expect(movedPlan.date(at: 11) == day(2026, 12, 5))
        #expect(movedPlan.date(at: 12) == nil)
    }

    @Test("A move can't go back to or before the payment before it")
    func outOfOrder() {
        let rule = RecurrenceRule(unit: .month, anchor: day(2026, 1, 20))
        #expect(rule.restarting(at: 9, on: day(2026, 9, 20)) == nil)
        #expect(rule.restarting(at: 9, on: day(2026, 9, 10)) == nil)
        #expect(rule.restarting(at: 0, on: day(2026, 1, 1))?.anchor == day(2026, 1, 1))
    }

    @Test("Paid records before the move still count; installment progress stays right")
    func history() throws {
        let item = RecurringItem(name: "Car", type: .installment, amount: Money(major: 45_000, .pkr),
                                 rule: RecurrenceRule(unit: .month, anchor: day(2026, 1, 10), limit: 12),
                                 trackedFrom: day(2026, 1, 10))
        var moved = item
        moved.rule = try #require(item.rule.restarting(at: 9, on: day(2026, 10, 5)))
        let records = (0..<9).map { OccurrenceRecord(itemID: item.id, scheduledDate: item.rule.date(at: $0)!, status: .paid) }
            + [OccurrenceRecord(itemID: item.id, scheduledDate: day(2026, 10, 5), status: .paid)]
        #expect(OccurrenceGenerator.paidCount(moved, records: records) == 10)
        let next = try #require(OccurrenceGenerator.next(moved, records: records, today: day(2026, 10, 6)))
        #expect(next.scheduledDate == day(2026, 11, 5))
        #expect(next.sequence == 11)
    }
}
