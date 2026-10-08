import Foundation
import Testing
@testable import UZeeCore

/// Namaz times and Qibla (owner request 2026-10-07), checked against the standard formulas.
@Suite("Prayer times and Qibla")
struct PrayerTests {
    let karachi = TimeZone(identifier: "Asia/Karachi")!

    func clock(_ date: Date, _ zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", parts.hour!, parts.minute!)
    }

    @Test("Karachi, 8 Oct 2026, Karachi method with Hanafi Asr")
    func karachiTimes() throws {
        let day = try #require(PrayerTimes.day(LocalDate(year: 2026, month: 10, day: 8), latitude: 24.8607, longitude: 67.0011,
                                               timeZone: karachi))
        #expect(clock(day.fajr, karachi) == "5:11")
        #expect(clock(day.sunrise, karachi) == "6:27")
        #expect(clock(day.dhuhr, karachi) == "12:21")
        #expect(clock(day.asr, karachi) == "16:33")
        #expect(clock(day.maghrib, karachi) == "18:12")
        #expect(clock(day.isha, karachi) == "19:28")
    }

    @Test("Windows run start to next start; Isha ends at the next Fajr; standard Asr is earlier")
    func windows() throws {
        let date = LocalDate(year: 2026, month: 10, day: 8)
        let windows = PrayerTimes.windows(date, latitude: 31.5204, longitude: 74.3587, timeZone: karachi)
        #expect(windows.map(\.prayer) == Prayer.allCases)
        #expect(clock(windows[0].start, karachi) == "4:40")
        #expect(clock(windows[0].end, karachi) == "6:01")
        #expect(windows[1].end == windows[2].start)
        #expect(windows[4].end > windows[4].start.addingTimeInterval(8 * 3_600))
        let hanafi = try #require(PrayerTimes.day(date, latitude: 31.5204, longitude: 74.3587, timeZone: karachi))
        let standard = try #require(PrayerTimes.day(date, latitude: 31.5204, longitude: 74.3587, timeZone: karachi, asr: .standard))
        #expect(standard.asr < hanafi.asr)
    }

    @Test("Qibla bearings: Karachi west, London south-east")
    func qibla() {
        #expect(abs(Qibla.bearing(latitude: 24.8607, longitude: 67.0011) - 267.74) < 0.1)
        #expect(abs(Qibla.bearing(latitude: 51.5074, longitude: -0.1278) - 118.99) < 0.1)
    }
}

@Suite("Prayer reminders")
struct PrayerReminderTests {
    @Test("One at each start still to come, only when on and placed")
    func reminders() {
        let zone = TimeZone(identifier: "Asia/Karachi")!
        var settings = PrayerSettings(latitude: 24.8607, longitude: 67.0011, notify: true)
        let noon = LocalDate(year: 2026, month: 10, day: 8).startDate(in: zone).addingTimeInterval(13 * 3_600)
        let planned = settings.reminders(from: noon, timeZone: zone, days: 2)
        #expect(planned.map(\.title) == ["Asr time", "Maghrib time", "Isha time", "Fajr time", "Dhuhr time", "Asr time", "Maghrib time", "Isha time"])
        #expect(planned[0].minuteOfDay == 16 * 60 + 33)
        settings.notify = false
        #expect(settings.reminders(from: noon, timeZone: zone).isEmpty)
        #expect(PrayerSettings(notify: true).reminders(from: noon, timeZone: zone).isEmpty)
    }
}
