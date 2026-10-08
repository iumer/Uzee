import SwiftUI
import UZeeCore

/// Namaz times and Qibla (owner request 2026-10-07): today's five windows for where you are
/// ("Asr · now · ends 6:12 pm"), a compass pointing to the Kaaba, the calculation method and reminders.
/// Worked out on the phone; works offline once the place is known.
struct PrayerView: View {
    @Bindable var session: AppSession
    @State private var locating = false
    @State private var problem: String?
    @State private var heading: Double?
    @State private var hasCompass = true

    var body: some View {
        let settings = session.prayer
        List {
            if settings.hasPlace {
                Section {
                    TimelineView(.everyMinute) { context in
                        let now = context.date
                        let windows = settings.windows(LocalDate(now, in: .current), timeZone: .current)
                        ForEach(windows, id: \.prayer) { window in
                            PrayerRow(window: window, now: now)
                        }
                    }
                } header: {
                    HStack {
                        Text(settings.city ?? "Your location")
                        Spacer()
                        Button(locating ? "Locating…" : "Update") { locate() }
                            .font(.caption.weight(.semibold)).textCase(nil)
                            .disabled(locating)
                    }
                } footer: {
                    Text("\(settings.method.name) · \(settings.asr.name) Asr. Each time runs until the next one starts; Fajr ends at sunrise.")
                }
                Section("Qibla") {
                    QiblaCompass(bearing: Qibla.bearing(latitude: settings.latitude ?? 0, longitude: settings.longitude ?? 0),
                                 heading: heading, hasCompass: hasCompass)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, UZSpacing.l)
                }
                Section {
                    Toggle("Remind me at each prayer", isOn: $session.prayer.notify)
                        .onChange(of: session.prayer.notify) { _, on in
                            if on { Task { _ = await session.calendar.requestNotifications(); session.rescheduleReminders() } }
                        }
                        .accessibilityIdentifier("prayer.notify")
                    Picker("Method", selection: $session.prayer.method) {
                        ForEach(PrayerMethod.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    Picker("Asr", selection: $session.prayer.asr) {
                        ForEach(AsrMethod.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                } footer: {
                    Text("Pakistan usually follows the Karachi method with Hanafi Asr. Times can differ by a few minutes from your local mosque.")
                }
            } else {
                Section {
                    VStack(spacing: UZSpacing.l) {
                        Image(systemName: "location.north.circle").font(.system(size: 44)).foregroundStyle(UZColor.tint)
                        Text("Namaz times and Qibla need your location. It stays on this iPhone.")
                            .multilineTextAlignment(.center).foregroundStyle(UZColor.label2)
                        Button(locating ? "Finding you…" : "Use my location") { locate() }
                            .buttonStyle(.borderedProminent)
                            .disabled(locating)
                            .accessibilityIdentifier("prayer.locate")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, UZSpacing.xl)
                }
            }
            if let problem {
                Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(UZColor.negative) }
            }
        }
        .navigationTitle("Namaz & Qibla")
        .onAppear {
            hasCompass = session.location.startHeading { value in
                Task { @MainActor in heading = value }
            }
        }
        .onDisappear { session.location.stopHeading() }
    }

    private func locate() {
        locating = true
        problem = nil
        Task {
            if !(await session.updatePrayerPlace()) {
                problem = "Couldn't find your location. Allow it for UZee in Settings › Privacy › Location Services."
            }
            locating = false
        }
    }
}

private struct PrayerRow: View {
    let window: PrayerWindow
    let now: Date

    var body: some View {
        let isNow = window.contains(now)
        let isPast = window.end <= now
        HStack {
            VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                HStack(spacing: UZSpacing.s) {
                    Text(window.prayer.name).font(.body.weight(isNow ? .semibold : .regular))
                    if isNow {
                        Text("Now").font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, UZSpacing.s).padding(.vertical, 2)
                            .background(UZColor.positive, in: .capsule)
                    }
                }
                Text("Ends \(window.end.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote).foregroundStyle(UZColor.label2)
            }
            Spacer()
            Text(window.start.formatted(date: .omitted, time: .shortened))
                .font(.body.weight(.semibold)).monospacedDigit()
        }
        .foregroundStyle(isPast ? UZColor.label3 : UZColor.label)
        .listRowBackground(isNow ? UZColor.tint.opacity(0.12) : nil)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("prayer.\(window.prayer.rawValue)")
    }
}

/// A compass dial that turns with the phone; the green arrow points to the Kaaba and the phone buzzes once
/// when you face it.
struct QiblaCompass: View {
    let bearing: Double
    let heading: Double?
    let hasCompass: Bool

    var body: some View {
        let turn = heading ?? 0
        let offset = Self.difference(bearing, turn)
        let facing = heading != nil && abs(offset) < 4
        VStack(spacing: UZSpacing.l) {
            ZStack {
                Circle().stroke(UZColor.fill, lineWidth: 10)
                ForEach(0..<4) { index in
                    Text(["N", "E", "S", "W"][index]).font(.caption.weight(.bold)).foregroundStyle(index == 0 ? UZColor.negative : UZColor.label2)
                        .offset(y: -98)
                        .rotationEffect(.degrees(Double(index) * 90))
                }
                .rotationEffect(.degrees(-turn))
                Image(systemName: "location.north.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(facing ? UZColor.positive : UZColor.tint)
                    .rotationEffect(.degrees(bearing - turn))
                Image(systemName: "building.columns.fill").font(.caption).foregroundStyle(UZColor.positive)
                    .offset(y: -70)
                    .rotationEffect(.degrees(bearing - turn))
            }
            .frame(width: 220, height: 220)
            .animation(.interpolatingSpring(stiffness: 120, damping: 18), value: turn)
            .sensoryFeedback(.success, trigger: facing) { _, new in new }
            Text(hasCompass ? (facing ? "You're facing the Qibla" : "Turn until the arrow points up · \(Int(bearing.rounded()))° from north")
                            : "Qibla is \(Int(bearing.rounded()))° from north (this device has no compass)")
                .font(.subheadline.weight(facing ? .semibold : .regular))
                .foregroundStyle(facing ? UZColor.positive : UZColor.label2)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(facing ? "Facing the Qibla" : "Qibla is \(Int(bearing.rounded())) degrees from north")
        .accessibilityIdentifier("prayer.qibla")
    }

    /// Signed difference in degrees, −180…180.
    static func difference(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }
}
