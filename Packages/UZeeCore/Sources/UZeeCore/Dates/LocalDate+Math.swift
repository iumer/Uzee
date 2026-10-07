import Foundation

/// Calendar arithmetic on days. Uses a fixed Gregorian calendar in UTC so results never depend on
/// the device's time zone (a LocalDate is already "the day in the user's zone").
extension LocalDate {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    var utcDate: Date { startDate(in: TimeZone(identifier: "UTC")!) }

    init(utc date: Date) {
        self.init(date, in: TimeZone(identifier: "UTC")!)
    }

    public static func daysIn(year: Int, month: Int) -> Int {
        let first = LocalDate(year: year, month: month, day: 1).utcDate
        return utc.range(of: .day, in: .month, for: first)?.count ?? 30
    }

    public var daysInMonth: Int { Self.daysIn(year: year, month: month) }

    /// The same day `months` later, clamped to the month's length (31 Jan + 1 month = 28/29 Feb).
    public func addingMonths(_ months: Int) -> LocalDate {
        let index = year * 12 + (month - 1) + months
        let y = index >= 0 ? index / 12 : (index - 11) / 12
        let m = index - y * 12 + 1
        return LocalDate(year: y, month: m, day: min(day, Self.daysIn(year: y, month: m)))
    }

    public func addingDays(_ days: Int) -> LocalDate {
        LocalDate(utc: Self.utc.date(byAdding: .day, value: days, to: utcDate) ?? utcDate)
    }

    /// Whole days from `self` to `other` (negative when `other` is earlier).
    public func days(to other: LocalDate) -> Int {
        Self.utc.dateComponents([.day], from: utcDate, to: other.utcDate).day ?? 0
    }

    /// 1 = Sunday … 7 = Saturday (Gregorian).
    public var weekday: Int { Self.utc.component(.weekday, from: utcDate) }

    public var firstOfMonth: LocalDate { LocalDate(year: year, month: month, day: 1) }
    public var lastOfMonth: LocalDate { LocalDate(year: year, month: month, day: daysInMonth) }

    /// "2026-10", for grouping by month.
    public var monthKey: String { String(description.prefix(7)) }
}
