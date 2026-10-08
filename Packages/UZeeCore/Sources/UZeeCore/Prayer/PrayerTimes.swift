import Foundation

/// How Fajr, Isha and Asr are worked out (owner picks; Karachi + Hanafi by default, as in Pakistan).
public enum PrayerMethod: String, CaseIterable, Sendable, Codable {
    case karachi, muslimWorldLeague, isna, ummAlQura, egypt

    public var name: String {
        switch self {
        case .karachi: "University of Islamic Sciences, Karachi"
        case .muslimWorldLeague: "Muslim World League"
        case .isna: "ISNA (North America)"
        case .ummAlQura: "Umm al-Qura, Makkah"
        case .egypt: "Egyptian General Authority"
        }
    }

    /// Sun angle below the horizon for Fajr, and for Isha (or minutes after Maghrib).
    var fajrAngle: Double {
        switch self {
        case .karachi, .muslimWorldLeague: 18
        case .isna: 15
        case .ummAlQura: 18.5
        case .egypt: 19.5
        }
    }

    var isha: (angle: Double?, minutesAfterMaghrib: Double?) {
        switch self {
        case .karachi: (18, nil)
        case .muslimWorldLeague: (17, nil)
        case .isna: (15, nil)
        case .ummAlQura: (nil, 90)
        case .egypt: (17.5, nil)
        }
    }
}

public enum AsrMethod: String, CaseIterable, Sendable, Codable {
    /// Shadow twice the object's length (Hanafi).
    case hanafi
    /// Shadow equal to the object's length (Shafi'i, Maliki, Hanbali).
    case standard

    public var name: String { self == .hanafi ? "Hanafi" : "Shafi'i, Maliki, Hanbali" }
    var shadowFactor: Double { self == .hanafi ? 2 : 1 }
}

public enum Prayer: String, CaseIterable, Sendable, Codable {
    case fajr, dhuhr, asr, maghrib, isha

    public var name: String {
        switch self {
        case .fajr: "Fajr"
        case .dhuhr: "Dhuhr"
        case .asr: "Asr"
        case .maghrib: "Maghrib"
        case .isha: "Isha"
        }
    }
}

/// One prayer's window: from its start to the start of the next (Fajr ends at sunrise, Isha at the next Fajr).
public struct PrayerWindow: Hashable, Sendable {
    public var prayer: Prayer
    public var start: Date
    public var end: Date

    public func contains(_ date: Date) -> Bool { start <= date && date < end }
}

/// Prayer times worked out on the device from the sun's position (the standard praytimes.org formulas):
/// no network, works anywhere. Times are for `timeZone` on the given day.
public enum PrayerTimes {
    public struct Day: Hashable, Sendable {
        public var fajr: Date
        public var sunrise: Date
        public var dhuhr: Date
        public var asr: Date
        public var maghrib: Date
        public var isha: Date

        public func start(of prayer: Prayer) -> Date {
            switch prayer {
            case .fajr: fajr
            case .dhuhr: dhuhr
            case .asr: asr
            case .maghrib: maghrib
            case .isha: isha
            }
        }
    }

    public static func day(_ date: LocalDate, latitude: Double, longitude: Double, timeZone: TimeZone,
                           method: PrayerMethod = .karachi, asr: AsrMethod = .hanafi) -> Day? {
        let noon = date.startDate(in: timeZone).addingTimeInterval(12 * 3_600)
        let offset = Double(timeZone.secondsFromGMT(for: noon)) / 3_600
        let jd = julian(date) - longitude / (15 * 24)

        func midday(_ t: Double) -> Double { mod(12 - sun(jd + t).equation, 24) }
        func angleTime(_ angle: Double, _ t: Double, before: Bool) -> Double? {
            let decl = sun(jd + t).declination
            let cosine = (-sin(rad(angle)) - sin(rad(decl)) * sin(rad(latitude))) / (cos(rad(decl)) * cos(rad(latitude)))
            guard (-1...1).contains(cosine) else { return nil }  // the sun never gets that low (far north in summer)
            let v = deg(acos(cosine)) / 15
            return midday(t) + (before ? -v : v)
        }
        func asrTime(_ t: Double) -> Double? {
            let decl = sun(jd + t).declination
            let angle = -deg(atan(1 / (asr.shadowFactor + tan(rad(abs(latitude - decl))))))
            return angleTime(angle, t, before: false)
        }

        var hours: [String: Double] = ["fajr": 5, "sunrise": 6, "dhuhr": 12, "asr": 13, "sunset": 18, "isha": 18]
        for _ in 0..<2 {
            let f = hours.mapValues { $0 / 24 }
            guard let fajr = angleTime(method.fajrAngle, f["fajr"]!, before: true),
                  let sunrise = angleTime(0.833, f["sunrise"]!, before: true),
                  let asrHour = asrTime(f["asr"]!),
                  let sunset = angleTime(0.833, f["sunset"]!, before: false) else { return nil }
            var isha = sunset + (method.isha.minutesAfterMaghrib ?? 0) / 60
            if let angle = method.isha.angle {
                guard let value = angleTime(angle, f["isha"]!, before: false) else { return nil }
                isha = value
            }
            hours = ["fajr": fajr, "sunrise": sunrise, "dhuhr": midday(f["dhuhr"]!), "asr": asrHour, "sunset": sunset, "isha": isha]
        }
        let adjust = offset - longitude / 15
        func time(_ key: String, extraMinutes: Double = 0) -> Date {
            let value = hours[key]! + adjust + extraMinutes / 60
            return date.startDate(in: timeZone).addingTimeInterval((value * 60).rounded() * 60)  // to the nearest minute
        }
        // Dhuhr a minute after the sun passes its highest point.
        return Day(fajr: time("fajr"), sunrise: time("sunrise"), dhuhr: time("dhuhr", extraMinutes: 1), asr: time("asr"),
                   maghrib: time("sunset"), isha: time("isha"))
    }

    /// The five windows of `date`, Isha running until the next day's Fajr.
    public static func windows(_ date: LocalDate, latitude: Double, longitude: Double, timeZone: TimeZone,
                               method: PrayerMethod = .karachi, asr: AsrMethod = .hanafi) -> [PrayerWindow] {
        guard let today = day(date, latitude: latitude, longitude: longitude, timeZone: timeZone, method: method, asr: asr) else { return [] }
        let nextFajr = day(date.addingDays(1), latitude: latitude, longitude: longitude, timeZone: timeZone, method: method, asr: asr)?.fajr
            ?? today.fajr.addingTimeInterval(86_400)
        return [PrayerWindow(prayer: .fajr, start: today.fajr, end: today.sunrise),
                PrayerWindow(prayer: .dhuhr, start: today.dhuhr, end: today.asr),
                PrayerWindow(prayer: .asr, start: today.asr, end: today.maghrib),
                PrayerWindow(prayer: .maghrib, start: today.maghrib, end: today.isha),
                PrayerWindow(prayer: .isha, start: today.isha, end: nextFajr)]
    }

    // MARK: Sun

    static func sun(_ jd: Double) -> (declination: Double, equation: Double) {
        let d = jd - 2_451_545.0
        let g = mod(357.529 + 0.98560028 * d, 360)
        let q = mod(280.459 + 0.98564736 * d, 360)
        let l = mod(q + 1.915 * sin(rad(g)) + 0.020 * sin(rad(2 * g)), 360)
        let e = 23.439 - 0.00000036 * d
        let ra = mod(deg(atan2(cos(rad(e)) * sin(rad(l)), cos(rad(l)))) / 15, 24)
        var equation = q / 15 - ra
        equation -= 24 * (equation / 24).rounded()
        return (deg(asin(sin(rad(e)) * sin(rad(l)))), equation)
    }

    static func julian(_ date: LocalDate) -> Double {
        var year = date.year, month = date.month
        if month <= 2 { year -= 1; month += 12 }
        let a = year / 100
        let b = 2 - a + a / 4
        return floor(365.25 * Double(year + 4_716)) + floor(30.6001 * Double(month + 1)) + Double(date.day + b) - 1_524.5
    }

    static func rad(_ value: Double) -> Double { value * .pi / 180 }
    static func deg(_ value: Double) -> Double { value * 180 / .pi }
    static func mod(_ value: Double, _ by: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: by)
        return r < 0 ? r + by : r
    }
}

/// Direction of the Kaaba (great circle), in degrees clockwise from true north.
public enum Qibla {
    public static let kaaba = (latitude: 21.4225, longitude: 39.8262)

    public static func bearing(latitude: Double, longitude: Double) -> Double {
        let r = PrayerTimes.rad, d = PrayerTimes.deg
        let k = (r(kaaba.latitude), r(kaaba.longitude)), here = (r(latitude), r(longitude))
        let angle = atan2(sin(k.1 - here.1), cos(here.0) * tan(k.0) - sin(here.0) * cos(k.1 - here.1))
        return PrayerTimes.mod(d(angle), 360)
    }
}
