import Foundation
import Testing
@testable import UZeeCore

private func rs(_ major: Int64) -> Money { Money(major: major, .pkr) }
private func day(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d) }

/// BUD unit parts: periods, percentages, lines and fire-once alerts (TEST_REGISTRY §BUD).
@Suite("Budget")
struct BudgetTests {
    @Test("BUD-010 calendar month periods")
    func calendarMonth() {
        let october = BudgetPeriod.containing(day(2026, 10, 6), kind: .calendarMonth)
        #expect(october.start == day(2026, 10, 1) && october.end == day(2026, 10, 31))
        #expect(october.previous.start == day(2026, 9, 1) && october.previous.end == day(2026, 9, 30))
        #expect(october.next.end == day(2026, 11, 30))
        #expect(BudgetPeriod.containing(day(2028, 2, 10), kind: .calendarMonth).end == day(2028, 2, 29))
    }

    @Test("BUD-011 salary cycle 21st–20th, short months and leap years")
    func salaryCycle() {
        let cycle = BudgetPeriodKind.salaryCycle(startDay: 21)
        let now = BudgetPeriod.containing(day(2026, 10, 6), kind: cycle)
        #expect(now.start == day(2026, 9, 21) && now.end == day(2026, 10, 20))
        #expect(BudgetPeriod.containing(day(2026, 10, 21), kind: cycle).start == day(2026, 10, 21))
        #expect(now.next.end == day(2026, 11, 20))
        let end31 = BudgetPeriodKind.salaryCycle(startDay: 31)
        let feb = BudgetPeriod.containing(day(2027, 2, 28), kind: end31)
        #expect(feb.start == day(2027, 2, 28) && feb.end == day(2027, 3, 30))
        #expect(BudgetPeriod.containing(day(2028, 2, 29), kind: end31).start == day(2028, 2, 29))
        #expect(BudgetPeriod.containing(day(2027, 1, 1), kind: cycle).start == day(2026, 12, 21))
        #expect(BudgetPeriodKind(storage: cycle.storageValue) == cycle)
        #expect(BudgetPeriodKind(storage: "junk") == .calendarMonth)
    }

    @Test("BUD-004 percentages are half-up basis points")
    func percentages() {
        let bp = BudgetCalculator.basisPoints(Money(minorUnits: 7_837_420, currency: .pkr), of: rs(235_000))
        #expect(bp == 3_335)
        #expect(BudgetCalculator.percentText(bp) == "33%")
        #expect(BudgetCalculator.basisPoints(rs(1), of: rs(0)) == 0)
        #expect(BudgetCalculator.percentText(9_950) == "100%")
    }

    @Test("BUD-005 over-by, warning and on-track lines")
    func lines() {
        let personal = BudgetLine(categoryID: UUID(), limit: rs(5_000), spent: rs(6_200))
        #expect(personal.overBy == rs(1_200))
        #expect(personal.state(warnPercent: 80) == .over)
        let food = BudgetLine(categoryID: UUID(), limit: rs(40_000), spent: rs(32_000))
        #expect(food.state(warnPercent: 80) == .warning)
        #expect(BudgetLine(categoryID: UUID(), limit: rs(40_000), spent: rs(31_999)).state(warnPercent: 80) == .onTrack)
        #expect(food.overBy == nil)
        #expect(food.remaining == rs(8_000))
    }

    @Test("BUD-008 alerts fire once per period and line")
    func alerts() {
        let id = UUID()
        let period = BudgetPeriod.containing(day(2026, 10, 6), kind: .calendarMonth)
        let summary = BudgetSummary(period: period, total: rs(235_000), spent: rs(78_374),
                                    lines: [BudgetLine(categoryID: id, limit: rs(5_000), spent: rs(6_200))], unbudgeted: [:])
        let first = BudgetAlerts.due(summary, warnPercent: 80, fired: [])
        #expect(first.count == 1 && first[0].state == .over && first[0].categoryID == id)
        #expect(BudgetAlerts.due(summary, warnPercent: 80, fired: Set(first.map(\.key))).isEmpty)
        #expect(summary.unassigned == rs(230_000))
        #expect(summary.left == rs(156_626))
    }

    @Test("LocalDate month and day arithmetic")
    func dateMath() {
        #expect(day(2026, 1, 31).addingMonths(1) == day(2026, 2, 28))
        #expect(day(2026, 12, 15).addingMonths(1) == day(2027, 1, 15))
        #expect(day(2026, 10, 6).addingDays(15) == day(2026, 10, 21))
        #expect(day(2026, 10, 6).days(to: day(2026, 10, 21)) == 15)
        #expect(day(2026, 10, 1).weekday == 5) // Thursday
        #expect(day(2026, 3, 1).addingMonths(-3) == day(2025, 12, 1))
    }

    @Test("A budget line named Loans counts lending and paying back; nothing else does")
    func loansLine() {
        let account = UUID()
        let loans = SpendCategory(type: .expense, name: "Loans", group: .other)
        let food = SpendCategory(type: .expense, name: "Food", group: .food)
        let october = BudgetPeriod.containing(day(2026, 10, 6), kind: .calendarMonth)
        func txn(_ kind: TransactionKind, _ amount: Int64, _ leg: Int64, category: UUID? = nil) -> MoneyTransaction {
            MoneyTransaction(kind: kind, occurredAt: Date(), localDate: day(2026, 10, 10), timeZoneID: "Asia/Karachi", amount: rs(amount),
                             categoryID: category, legs: [TransactionLeg(accountID: account, amount: rs(leg), role: .main)])
        }
        let rows = [txn(.loanOut, 20_000, -20_000), txn(.repayment, 5_000, -5_000), txn(.repayment, 3_000, 3_000),
                    txn(.loanIn, 50_000, 50_000), txn(.expense, 4_000, -4_000, category: food.id)]
        let plan = BudgetPlan(periodStart: october.start, total: rs(100_000), limits: [loans.id: rs(30_000)])
        let summary = BudgetCalculator.summary(plan: plan, period: october, transactions: rows, categories: [loans, food], base: .pkr, rates: [:])
        #expect(summary.lines.first { $0.categoryID == loans.id }?.spent == rs(25_000))
        #expect(summary.spent == rs(29_000))
        #expect(summary.unbudgeted[food.id] == rs(4_000))
        // Without a Loans line, loans don't count at all.
        let plain = BudgetCalculator.summary(plan: BudgetPlan(periodStart: october.start, total: rs(100_000)), period: october,
                                             transactions: rows, categories: [loans, food], base: .pkr, rates: [:])
        #expect(plain.spent == rs(4_000))
    }
}
