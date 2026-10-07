import Foundation
import Testing
import GRDB
import UZeeCore
@testable import UZeeData

private func rs(_ major: Int64) -> Money { Money(major: major, .pkr) }

/// BUD integration tests on the sample dataset (October 2026 and the April–September history).
@Suite("Budget store")
struct BudgetStoreTests {
    func sample() throws -> (AppDatabase, LedgerStore, BudgetStore) {
        let database = try AppDatabase.inMemory()
        try SampleDataService(database: database).load()
        return (database, LedgerStore(database: database), BudgetStore(database: database))
    }

    func summary(_ store: LedgerStore, _ budgets: BudgetStore, month: Int) throws -> BudgetSummary {
        let snapshot = try store.snapshot()
        let period = BudgetPeriod.containing(LocalDate(year: 2026, month: month, day: 6), kind: .calendarMonth)
        let plan = try #require(try budgets.plan(for: period))
        return BudgetCalculator.summary(plan: plan, period: period, transactions: try store.transactions(),
                                        categories: snapshot.categories, base: .pkr, rates: snapshot.rates)
    }

    func group(_ key: String, _ store: LedgerStore) throws -> UUID {
        try store.categories().first { $0.systemKey == key }!.id
    }

    @Test("BUD-001 October: Rs 78,374 spent, Rs 156,626 left, 33% used, Rs 3,000 unassigned, Personal over by Rs 1,200")
    func october() throws {
        let (_, store, budgets) = try sample()
        let october = try summary(store, budgets, month: 10)
        #expect(MoneyFormatter.string(october.spent) == "Rs 78,374")
        #expect(MoneyFormatter.string(october.left) == "Rs 156,626")
        #expect(BudgetCalculator.percentText(october.usedBasisPoints) == "33%")
        #expect(october.unassigned == rs(3_000))
        let personal = october.lines.first { $0.categoryID == (try? group("personal", store)) }!
        #expect(personal.overBy == rs(1_200))
        let spent = Dictionary(uniqueKeysWithValues: try october.lines.map { line in
            (try store.categories().first { $0.id == line.categoryID }!.name, MoneyFormatter.string(line.spent))
        })
        #expect(spent == ["Office": "Rs 38,000", "Transport": "Rs 16,367", "Food": "Rs 15,470", "Financial": "Rs 0",
                          "Subscriptions": "Rs 837", "Utilities": "Rs 1,500", "Personal": "Rs 6,200"])
        #expect(october.unbudgeted.isEmpty)
    }

    @Test("BUD-002 transfers, loans and income never count; USD at the table rate")
    func neutral() throws {
        let (_, store, budgets) = try sample()
        let october = try summary(store, budgets, month: 10)
        // The $500 transfer, Rs 20,000 loan and $250 reimbursement are in October but not in spending.
        #expect(october.spent.minorUnits == 7_837_420)
    }

    @Test("BUD-012 September and the six-month record: kept 5 of 6, August over")
    func history() throws {
        let (_, store, budgets) = try sample()
        let september = try summary(store, budgets, month: 9)
        #expect(MoneyFormatter.string(september.spent) == "Rs 231,565")
        #expect(MoneyFormatter.string(september.unbudgeted[try group("health", store)]!) == "Rs 4,500")
        var kept = 0
        var over: [Int] = []
        for month in 4...9 {
            let s = try summary(store, budgets, month: month)
            if s.isOver { over.append(month) } else { kept += 1 }
        }
        #expect(kept == 5 && over == [8])
    }

    @Test("BUD-006 a new period copies the previous limits; no rollover")
    func copyForward() throws {
        let (_, store, budgets) = try sample()
        let november = BudgetPeriod.containing(LocalDate(year: 2026, month: 11, day: 1), kind: .calendarMonth)
        let plan = try #require(try budgets.plan(for: november))
        #expect(plan.total == rs(235_000))
        #expect(plan.limits[try group("food", store)] == rs(30_000))
        #expect(try budgets.existingPlans()[november.start] != nil)
    }

    @Test("BUD-003 saving limits; a real budget wins over the sample one and survives sample removal")
    func saveOwn() throws {
        let (database, store, budgets) = try sample()
        let food = try group("food", store)
        let start = LocalDate(year: 2026, month: 10, day: 1)
        try budgets.save(BudgetPlan(periodStart: start, total: rs(200_000), limits: [food: rs(40_000)]))
        let period = BudgetPeriod.containing(start, kind: .calendarMonth)
        #expect(try budgets.plan(for: period)?.total == rs(200_000))
        try SampleDataService(database: database).removeAll()
        #expect(try budgets.plan(for: period)?.limits == [food: rs(40_000)])
    }

    @Test("BUD-009 settings and fire-once alert keys")
    func settings() throws {
        let (_, _, budgets) = try sample()
        #expect(try budgets.settings() == BudgetStore.Settings())
        try budgets.setSettings(.init(periodKind: .salaryCycle(startDay: 21), warnPercent: 90))
        #expect(try budgets.settings().periodKind == .salaryCycle(startDay: 21))
        #expect(try budgets.settings().warnPercent == 90)
        try budgets.markFired(["a", "a", "b"])
        #expect(try budgets.firedAlerts() == ["a", "b"])
    }
}
