import Foundation

/// Wise's mid-market rates (CUR-03): the same numbers wise.com shows on its converter, live and day by day.
/// These are the keyless endpoints behind wise.com's rate chart, so every reply is checked and anything odd is
/// ignored (UZee then keeps the last rate it had).
public enum WiseRates {
    /// One point on the rate chart: `value` units of the target per 1 of the source, at `time` (ms since 1970, UTC).
    public struct Point: Equatable, Sendable {
        public let value: Decimal
        public let time: Int64

        public init(value: Decimal, time: Int64) {
            self.value = value
            self.time = time
        }

        /// The UTC calendar day of this point.
        public var day: LocalDate {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let parts = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: TimeInterval(time / 1000)))
            return LocalDate(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
        }
    }

    public static func liveURL(_ source: Currency, _ target: Currency) -> URL {
        URL(string: "https://wise.com/rates/live?source=\(source.code)&target=\(target.code)")!
    }

    /// Daily points for the last `days` days, ending today.
    public static func historyURL(_ source: Currency, _ target: Currency, days: Int) -> URL {
        URL(string: "https://wise.com/rates/history?source=\(source.code)&target=\(target.code)&length=\(max(2, days))&resolution=daily&unit=day")!
    }

    /// The chart endpoints to try, in order, for a history reaching `days` back: Wise's site uses
    /// `history+live`; long spans may need month or year units instead of days.
    public static func historyURLs(_ source: Currency, _ target: Currency, days: Int) -> [URL] {
        let pair = "source=\(source.code)&target=\(target.code)"
        let months = days / 30 + 2
        let years = days / 365 + 1
        return [
            "https://wise.com/rates/history+live?\(pair)&length=\(max(2, days))&resolution=daily&unit=day",
            "https://wise.com/rates/history+live?\(pair)&length=\(months)&resolution=daily&unit=month",
            "https://wise.com/rates/history+live?\(pair)&length=\(years)&resolution=daily&unit=year",
            "https://wise.com/rates/history?\(pair)&length=\(max(2, days))&resolution=daily&unit=day",
        ].compactMap { URL(string: $0) }
    }

    /// How many days of history to ask for so that `day` is included.
    public static func daysBack(to day: LocalDate, today: LocalDate) -> Int {
        max(2, day.days(to: today) + 3)
    }

    /// The live rate from `{"source":"USD","target":"PKR","value":278.7,"time":…}` (or a list, last point wins).
    public static func parseLive(_ data: Data) -> Decimal? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return point(object)?.value }
        return parseHistory(data).last?.value
    }

    /// The points from `[{"value":278.7,"time":…}, …]`, oldest first. Junk (an HTML challenge page, zero or
    /// absurd values) gives an empty list.
    public static func parseHistory(_ data: Data) -> [Point] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list.compactMap(point).sorted { $0.time < $1.time }
    }

    /// The rate on `day`: that day's last point, or the latest one in the 4 days before (weekends, holidays).
    public static func rate(on day: LocalDate, in points: [Point]) -> Decimal? {
        let before = points.filter { $0.day <= day }
        guard let last = before.last, last.day.days(to: day) <= 4 else { return nil }
        return last.value
    }

    private static func point(_ object: [String: Any]) -> Point? {
        guard let number = object["value"] as? NSNumber, let time = (object["time"] as? NSNumber)?.int64Value else { return nil }
        // Through text, so 278.7 stays 278.7 rather than 278.69999…; four decimals, like Wise shows.
        guard let exact = Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let value = Rounding.halfUp(exact, scale: 4)
        guard value > 0, value < 1_000_000 else { return nil }
        return Point(value: value, time: time)
    }
}
