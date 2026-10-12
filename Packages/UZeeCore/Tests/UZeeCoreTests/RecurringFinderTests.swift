import Foundation
import Testing
@testable import UZeeCore

private func day(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d) }
private func rs(_ major: Int64) -> Money { Money(major: major, .pkr) }
private func out(_ date: LocalDate, _ payee: String, _ amount: Int64) -> RecurringFinder.Payment {
    RecurringFinder.Payment(date: date, payee: payee, amount: rs(amount), isMoneyIn: false)
}

/// OWN-024: monthly repeats found in an imported statement. Synthetic rows only (the repo is public).
@Suite("Recurring finder")
struct RecurringFinderTests {
    let today = day(2026, 10, 12)

    @Test("A subscription on the same day three months running is found, with the next date")
    func subscription() {
        let rows = [out(day(2026, 7, 5), "NETFLIX.COM 8812", 1_100), out(day(2026, 8, 5), "NETFLIX.COM 9921", 1_100),
                    out(day(2026, 9, 6), "NETFLIX.COM 1034", 1_100), out(day(2026, 9, 14), "Grocer Mart", 4_000)]
        let found = RecurringFinder.find(rows, today: today)
        #expect(found.count == 1)
        let netflix = found.first
        #expect(netflix?.type == .subscription)
        #expect(netflix?.months == 3)
        #expect(netflix?.varies == false)
        #expect(netflix?.day == 5)
        #expect(netflix?.nextDate == day(2026, 11, 5))
    }

    @Test("A utility bill that varies a little and moves across the month end still counts")
    func utilityAcrossMonthEnd() {
        let rows = [out(day(2026, 7, 29), "K Electric bill", 9_000), out(day(2026, 8, 31), "K Electric bill", 11_500),
                    out(day(2026, 10, 2), "K Electric bill", 10_200)]
        let found = RecurringFinder.find(rows, today: today)
        #expect(found.first?.type == .utility)
        #expect(found.first?.varies == true)
        #expect(found.first?.nextDate == day(2026, 11, 2))
    }

    @Test("One-offs, twice-a-month shops, big swings, far-apart days and existing bills are left out")
    func notRecurring() {
        let rows = [
            out(day(2026, 8, 3), "Cafe", 500),
            out(day(2026, 8, 10), "Fuel Stop", 6_000), out(day(2026, 8, 24), "Fuel Stop", 6_000), out(day(2026, 9, 10), "Fuel Stop", 6_000),
            out(day(2026, 8, 12), "Electronics Hub", 2_000), out(day(2026, 9, 12), "Electronics Hub", 9_000),
            out(day(2026, 8, 2), "Tailor", 3_000), out(day(2026, 9, 18), "Tailor", 3_000),
            out(day(2026, 8, 20), "Spotify P0A1", 300), out(day(2026, 9, 20), "Spotify P0A2", 300),
        ]
        #expect(RecurringFinder.find(rows, existingNames: ["Spotify"], today: today).isEmpty)
    }

    @Test("Salary coming in is found as salary")
    func salary() {
        let rows = [RecurringFinder.Payment(date: day(2026, 8, 25), payee: "ACME LTD SALARY AUG", amount: rs(200_000), isMoneyIn: true),
                    RecurringFinder.Payment(date: day(2026, 9, 25), payee: "ACME LTD SALARY SEP", amount: rs(200_000), isMoneyIn: true)]
        let found = RecurringFinder.find(rows, today: today)
        #expect(found.first?.type == .salary)
        #expect(found.first?.nextDate == day(2026, 10, 25))
    }

    @Test("Day distance wraps around the month end")
    func dayDistance() {
        #expect(RecurringFinder.dayDistance(30, 2) == 3)
        #expect(RecurringFinder.dayDistance(5, 9) == 4)
        #expect(RecurringFinder.key("NETFLIX.COM 8812") == "netflix com")
    }
}
