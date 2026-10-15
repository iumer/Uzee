import Foundation
import UZeeCore

/// The market rate (as Google shows it) and money services' own rates, for Settings › Exchange rate
/// (owner, 2026-10-15). Nil when a rate can't be read; the screen then shows the market rate in its place.
public actor OtherRateFetcher {
    public static let shared = OtherRateFetcher()

    public init() {}

    public func market(_ source: Currency, in target: Currency) async -> Decimal? {
        for url in MarketRates.urls(source) {
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            guard let data = await Self.load(request), let rate = MarketRates.parse(data, source: source, target: target) else { continue }
            return rate
        }
        return nil
    }

    /// Only Western Union can be asked so far; the others come back nil (shown with the market rate).
    public func provider(_ provider: RateProvider, _ source: Currency, in target: Currency) async -> Decimal? {
        switch provider {
        case .westernUnion:
            var request = URLRequest(url: WesternUnionRates.url, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.httpBody = WesternUnionRates.body(source, target)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
                             forHTTPHeaderField: "User-Agent")
            guard let data = await Self.load(request) else { return nil }
            return WesternUnionRates.parse(data)
        default:
            return nil
        }
    }

    private static func load(_ request: URLRequest) async -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
