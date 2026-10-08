import Foundation

/// Future dates and times as people say them, for reminders made by voice (VOX-04):
/// "tomorrow", "on Friday", "in 3 days", "next week", "on the 5th", "20 October"; "at 5 pm", "5:30", "in the evening".
public enum ReminderPhrase {
    static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    public static func date(_ text: String, today: LocalDate) -> LocalDate? {
        let t = " " + VoiceRuleParser.normalise(text) + " "
        if t.contains(" day after tomorrow ") { return today.addingDays(2) }
        if t.contains(" tomorrow ") || t.contains(" kal ") { return today.addingDays(1) }
        if t.contains(" today ") || t.contains(" tonight ") || t.contains(" aaj ") { return today }
        if t.contains(" next week ") { return today.addingDays(7) }
        if t.contains(" next month ") { return today.addingMonths(1) }
        let words = t.split(separator: " ").map(String.init)
        for (index, word) in words.enumerated() {
            // "in 3 days", "in 2 weeks"
            if word == "in", index + 2 < words.count, let n = Int(words[index + 1]) ?? numberWord(words[index + 1]) {
                if words[index + 2].hasPrefix("day") { return today.addingDays(n) }
                if words[index + 2].hasPrefix("week") { return today.addingDays(7 * n) }
                if words[index + 2].hasPrefix("month") { return today.addingMonths(n) }
            }
            if let weekday = weekdays.firstIndex(of: word) {
                // The next one after today ("on Friday" said on a Friday means a week later).
                let ahead = (weekday + 1 - today.weekday + 7) % 7
                return today.addingDays(ahead == 0 ? 7 : ahead)
            }
        }
        if let found = TextScan.dates(in: text, defaultYear: today.year).first?.date {
            return found < today ? LocalDate(year: found.year + 1, month: found.month, day: found.day) : found
        }
        for (index, word) in words.enumerated() where index > 0 && ["on", "the"].contains(words[index - 1]) {
            let digits = word.prefix { $0.isNumber }
            guard let day = Int(digits), ["st", "nd", "rd", "th"].contains(String(word.dropFirst(digits.count))), (1...31).contains(day) else { continue }
            var month = today.firstOfMonth
            if day < today.day { month = month.addingMonths(1) }
            return LocalDate(year: month.year, month: month.month, day: min(day, month.daysInMonth))
        }
        return nil
    }

    /// Minutes after midnight, or nil when no time was said.
    public static func minuteOfDay(_ text: String) -> Int? {
        let t = " " + text.lowercased().replacingOccurrences(of: ".", with: "") + " "
        let pattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(t.startIndex..., in: t)
        for match in regex.matches(in: t, range: range) {
            guard let hourRange = Range(match.range(at: 1), in: t), var hour = Int(t[hourRange]) else { continue }
            let minute = Range(match.range(at: 2), in: t).flatMap { Int(t[$0]) }
            let meridiem = Range(match.range(at: 3), in: t).map { String(t[$0]) }
            // A bare number is a time only after "at" ("at 5"), so "3 days" isn't 3 o'clock.
            let before = t[..<hourRange.lowerBound].trimmingCharacters(in: .whitespaces)
            guard minute != nil || meridiem != nil || before.hasSuffix("at") else { continue }
            if meridiem == "pm", hour < 12 { hour += 12 }
            if meridiem == "am", hour == 12 { hour = 0 }
            if meridiem == nil, minute == nil, hour < 8 { hour += 12 }  // "at 5" means 5 pm
            guard (0...23).contains(hour), (0...59).contains(minute ?? 0) else { continue }
            return hour * 60 + (minute ?? 0)
        }
        if t.contains(" morning ") { return 9 * 60 }
        if t.contains(" afternoon ") { return 14 * 60 }
        if t.contains(" evening ") { return 18 * 60 }
        if t.contains(" night ") || t.contains(" tonight ") { return 21 * 60 }
        return nil
    }

    public struct Request: Equatable, Sendable {
        public var title: String
        public var date: LocalDate
        public var minuteOfDay: Int?
        public var amount: Money?

        public init(title: String, date: LocalDate, minuteOfDay: Int? = nil, amount: Money? = nil) {
            self.title = title
            self.date = date
            self.minuteOfDay = minuteOfDay
            self.amount = amount
        }
    }

    /// "Remind me to pay the plumber 5,000 on Friday at 5 pm" → a reminder. Nil when it isn't a reminder
    /// request or has no day (the caller then asks which day).
    public static func request(_ sentence: String, today: LocalDate, currency: Currency) -> Request? {
        let lower = sentence.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard lower.hasPrefix("remind me") else { return nil }
        var rest = String(lower.dropFirst("remind me".count)).trimmingCharacters(in: .whitespaces)
        for lead in ["to ", "about ", "that ", "of "] where rest.hasPrefix(lead) { rest = String(rest.dropFirst(lead.count)); break }
        guard let date = date(rest, today: today) else { return nil }
        var cut = rest.endIndex
        for marker in [" tomorrow", " today", " tonight", " day after", " on ", " at ", " in ", " next ", " this "] + weekdays.map({ " " + $0 }) {
            if let range = rest.range(of: marker), range.lowerBound < cut { cut = range.lowerBound }
        }
        var title = String(rest[..<cut]).trimmingCharacters(in: .whitespaces)
        // Times ("5 pm", "at 5", "5:30") aren't amounts.
        let withoutTimes = rest.replacingOccurrences(of: #"(\bat\s+\d{1,2}(:\d{2})?|\d{1,2}(:\d{2})?\s*(am|pm)|\d{1,2}:\d{2})"#,
                                                     with: " ", options: .regularExpression)
        let amount = AmountPhrase.find(in: withoutTimes).flatMap { try? Money.fromMajor($0.value, $0.currency ?? currency) }
        if title.isEmpty { title = "Reminder" }
        title = title.prefix(1).uppercased() + title.dropFirst()
        return Request(title: title, date: date, minuteOfDay: minuteOfDay(rest), amount: amount)
    }

    static func numberWord(_ word: String) -> Int? {
        ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "ten": 10, "a": 1, "an": 1][word]
    }
}
