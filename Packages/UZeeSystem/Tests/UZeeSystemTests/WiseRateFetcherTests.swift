import Foundation
import Testing
import UZeeCore
@testable import UZeeSystem

/// CUR-03 against the real wise.com (needs the internet; skipped offline): today's USD→PKR rate and the rate on
/// a day about seven months back both come back and look like rupees per dollar.
@Suite("Wise rates, live")
struct WiseRateFetcherTests {
    @Test("Live and dated USD→PKR from wise.com")
    func liveAndDated() async {
        let fetcher = WiseRateFetcher()
        guard let live = await fetcher.live(.usd, in: .pkr) else {
            print("Wise rates: wise.com not reachable or refused the request")
            return
        }
        print("Wise rates: live USD→PKR \(live)")
        #expect(live > 150 && live < 600)
        let today = LocalDate(Date(), in: TimeZone(identifier: "UTC")!)
        let past = today.addingDays(-210)
        // Which chart endpoint answers (printed so a failure says what Wise sent back).
        for url in WiseRates.historyURLs(.usd, .pkr, days: WiseRates.daysBack(to: past, today: today)) {
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let reply = try? await URLSession.shared.data(for: request)
            let status = (reply?.1 as? HTTPURLResponse)?.statusCode ?? 0
            let points = reply.map { WiseRates.parseHistory($0.0) } ?? []
            let head = reply.map { String(decoding: $0.0.prefix(120), as: UTF8.self) } ?? "no reply"
            print("Wise rates: \(url.absoluteString) → \(status), \(points.count) points, first \(points.first.map { "\($0.day)" } ?? "-"), \(head)")
        }
        let dated = await fetcher.rate(.usd, in: .pkr, on: past, today: today)
        print("Wise rates: \(past) USD→PKR \(dated.map { "\($0)" } ?? "none")")
        #expect(dated != nil)
        if let dated { #expect(dated > 150 && dated < 600) }
    }
}
