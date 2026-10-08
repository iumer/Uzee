import Foundation
import Testing
@testable import UZeeCore

/// CUR-03 live and dated USD→PKR rates from Wise, read from the shapes wise.com's rate chart returns.
@Suite("Wise rates")
struct WiseRatesTests {
    /// Midday UTC on a day, in ms.
    func ms(_ year: Int, _ month: Int, _ day: Int) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        return date.timeIntervalSince1970 * 1000
    }

    @Test("Live rate from one object, four decimals")
    func live() {
        let data = Data(#"{"source":"USD","target":"PKR","value":278.7034999,"time":1791478000000}"#.utf8)
        #expect(WiseRates.parseLive(data) == Decimal(string: "278.7035"))
    }

    @Test("A Cloudflare page, an empty list or zero is ignored")
    func junk() {
        #expect(WiseRates.parseLive(Data("<html>Just a moment…</html>".utf8)) == nil)
        #expect(WiseRates.parseHistory(Data("[]".utf8)).isEmpty)
        #expect(WiseRates.parseLive(Data(#"{"value":0,"time":1}"#.utf8)) == nil)
    }

    @Test("Rate on a past day; a weekend uses Friday's; too far back gives nothing")
    func onDay() throws {
        let json = "[" + [(2026, 3, 12, "279.10"), (2026, 3, 13, "279.25"), (2026, 3, 16, "279.40")]
            .map { #"{"source":"USD","target":"PKR","value":\#($0.3),"time":\#(Int(ms($0.0, $0.1, $0.2)))}"# }
            .joined(separator: ",") + "]"
        let points = WiseRates.parseHistory(Data(json.utf8))
        #expect(points.count == 3)
        #expect(WiseRates.rate(on: LocalDate(year: 2026, month: 3, day: 13), in: points) == Decimal(string: "279.25"))
        #expect(WiseRates.rate(on: LocalDate(year: 2026, month: 3, day: 14), in: points) == Decimal(string: "279.25"))
        #expect(WiseRates.rate(on: LocalDate(year: 2026, month: 3, day: 16), in: points) == Decimal(string: "279.4"))
        #expect(WiseRates.rate(on: LocalDate(year: 2026, month: 3, day: 1), in: points) == nil)
        #expect(WiseRates.rate(on: LocalDate(year: 2026, month: 3, day: 25), in: points) == nil)
    }

    @Test("History long enough to reach the day")
    func daysBack() {
        #expect(WiseRates.daysBack(to: LocalDate(year: 2026, month: 3, day: 14), today: LocalDate(year: 2026, month: 10, day: 8)) == 211)
        #expect(WiseRates.historyURL(.usd, .pkr, days: 211).absoluteString
                == "https://wise.com/rates/history?source=USD&target=PKR&length=211&resolution=daily&unit=day")
    }
}
