import Foundation
import Testing
@testable import UZeeCore

/// Owner, 2026-10-15: add transactions from screenshots of a bank app, an order email or a notification.
/// Made-up text only (the repo is public).
@Suite("Screenshots")
struct ScreenshotTests {
    let today = LocalDate(year: 2026, month: 10, day: 15)

    @Test("A bank app's list: a row per amount, with the day heading above")
    func appList() {
        let lines = ["Transactions", "Today", "Grocer Mart", "-Rs 1,250.00", "Salary October", "+Rs 50,000.00",
                     "Yesterday", "Raast transfer to Other Person", "-Rs 3,000", "Available balance Rs 80,000.00"]
        let reading = ScreenshotParser.read(lines: lines, currency: .pkr, today: today)
        #expect(reading.rows.count == 3)
        #expect(reading.rows[0].amount == -1_250)
        #expect(reading.rows[0].date == today)
        #expect(reading.rows[0].description.lowercased().contains("grocer mart"))
        #expect(reading.rows[1].amount == 50_000)
        #expect(reading.rows[2].date == today.addingDays(-1))
        #expect(reading.rows[2].amount == -3_000)
        #expect(reading.currencyCode == "PKR")
    }

    @Test("Dates printed under each row, without a year")
    func datesBelow() {
        let lines = ["Foodpanda", "Rs. 2,400.00", "12 Oct, 8:15 PM", "Daraz", "Rs. 5,999.00", "3 Oct, 1:02 PM"]
        let rows = ScreenshotParser.read(lines: lines, currency: .pkr, today: today).rows
        #expect(rows.count == 2)
        #expect(rows[0].date == LocalDate(year: 2026, month: 10, day: 12))
        #expect(rows[1].date == LocalDate(year: 2026, month: 10, day: 3))
        #expect(rows.allSatisfy { $0.amount < 0 })
        #expect(rows[1].description == "Daraz")
    }

    @Test("An order email is one payment: its total")
    func order() {
        let lines = ["Your order is confirmed", "Order #123456", "Chicken burger x2   Rs 1,200.00", "Fries   Rs 300.00",
                     "Subtotal   Rs 1,500.00", "Delivery fee   Rs 99.00", "Total   Rs 1,599.00"]
        let reading = ScreenshotParser.read(lines: lines, currency: .pkr, today: today)
        #expect(reading.rows.count == 1)
        #expect(reading.rows.first?.amount == -1_599)
    }

    @Test("A payment notification is one row")
    func notification() {
        let lines = ["Easypaisa", "You have received Rs. 2,000.00 from Test User"]
        let reading = ScreenshotParser.read(lines: lines, currency: .pkr, today: today)
        #expect(reading.rows.count == 1)
        #expect(reading.rows.first?.amount == 2_000)
    }
}
