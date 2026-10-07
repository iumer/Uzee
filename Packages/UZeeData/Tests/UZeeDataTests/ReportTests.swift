import Foundation
import Testing
import UZeeCore
@testable import UZeeData

private func rs(_ major: Int64) -> Money { Money(major: major, .pkr) }
private func day(_ m: Int, _ d: Int) -> LocalDate { LocalDate(year: 2026, month: m, day: d) }

/// RPT figures on the sample dataset (TEST_REGISTRY §RPT, dataset "Reports").
@Suite("Reports")
struct ReportTests {
    @Test("RPT-001 October where it went: Office 48% · Transport 21% · Food 20% · Personal 8% · Utilities 2% · Subscriptions 1%")
    func october() throws {
        let database = try AppDatabase.inMemory()
        try SampleDataService(database: database).load()
        let ledger = LedgerStore(database: database)
        let snapshot = try ledger.snapshot()
        let shares = ReportCalculator.byGroup(try ledger.transactions(), from: day(10, 1), through: day(10, 31),
                                              categories: snapshot.categories, base: .pkr, rates: snapshot.rates)
        let named = shares.map { (snapshot.category($0.categoryID)?.name ?? "?", $0.percent) }
        #expect(named.map(\.0) == ["Office", "Transport", "Food", "Personal", "Utilities", "Subscriptions"])
        #expect(named.map(\.1) == [48, 21, 20, 8, 2, 1])
        #expect(shares.first?.amount == rs(38_000))
    }

    @Test("RPT-002 September: income Rs 560,000, spending Rs 231,565, net +Rs 328,435; six months of history")
    func september() throws {
        let database = try AppDatabase.inMemory()
        try SampleDataService(database: database).load()
        let ledger = LedgerStore(database: database)
        let rates = try ledger.rates()
        let months = ReportCalculator.months(try ledger.transactions(), from: day(4, 1), through: day(9, 30), base: .pkr, rates: rates)
        #expect(months.count == 6)
        let september = months.last!
        #expect(september.income == rs(560_000))
        #expect(Money(minorUnits: (september.spending.minorUnits + 50) / 100 * 100, currency: .pkr) == rs(231_565))
        #expect(september.net.minorUnits / 100 == 328_434 || september.net.minorUnits / 100 == 328_435)
        #expect(months.map { $0.spending.minorUnits / 100_000 } == [198, 205, 226, 219, 248, 231])
    }
}
