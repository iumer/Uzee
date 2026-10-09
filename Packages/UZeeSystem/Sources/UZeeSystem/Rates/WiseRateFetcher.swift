import Foundation
import UZeeCore

/// Fetches Wise's USD→PKR (or any pair) mid-market rate, live or for a past day (CUR-03). Returns nil when Wise
/// can't be reached or answers with something unexpected; UZee then keeps its last rate.
public actor WiseRateFetcher {
    public static let shared = WiseRateFetcher()

    /// Daily history per pair, kept for an hour so a few backdated entries don't ask Wise every time.
    private var history: [String: (fetched: Date, days: Int, points: [WiseRates.Point])] = [:]

    public init() {}

    public func live(_ source: Currency, in target: Currency) async -> Decimal? {
        guard let data = await Self.get(WiseRates.liveURL(source, target)) else { return nil }
        return WiseRates.parseLive(data)
    }

    /// The rate on `day` (UTC day, as Wise's chart). Today asks for the live rate.
    public func rate(_ source: Currency, in target: Currency, on day: LocalDate, today: LocalDate) async -> Decimal? {
        if day >= today { return await live(source, in: target) }
        let key = source.code + target.code
        let days = WiseRates.daysBack(to: day, today: today)
        if let cached = history[key], cached.days >= days, Date().timeIntervalSince(cached.fetched) < 3600,
           let rate = WiseRates.rate(on: day, in: cached.points) {
            return rate
        }
        // Try each chart endpoint until one has a point on (or just before) the day.
        for url in WiseRates.historyURLs(source, target, days: days) {
            guard let data = await Self.get(url) else { continue }
            let points = WiseRates.parseHistory(data)
            guard let rate = WiseRates.rate(on: day, in: points) else { continue }
            history[key] = (Date(), days, points)
            return rate
        }
        return nil
    }

    private static func get(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        // Wise's site answers browsers; a plain app request can be turned away.
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
