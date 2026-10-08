import SwiftUI

/// The UZee helper's face: the wallet logo in a soft glow that breathes while listening, ripples while
/// speaking and turns slowly while thinking. Still with Reduce Motion.
struct HelperOrb: View {
    enum Mood: Equatable { case idle, listening, thinking, speaking }

    let mood: Mood
    var size: CGFloat = 120
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    static let colors: [Color] = [Color(red: 0.20, green: 0.78, blue: 0.55), Color(red: 0.25, green: 0.55, blue: 0.98),
                                          Color(red: 0.98, green: 0.80, blue: 0.25), Color(red: 0.20, green: 0.78, blue: 0.55)]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || mood == .idle)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSince(start)
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    Circle()
                        .fill(AngularGradient(colors: Self.colors, center: .center,
                                              angle: .degrees(t * (mood == .thinking ? 120 : 30) + Double(ring) * 40)))
                        .frame(width: size, height: size)
                        .scaleEffect(scale(ring: ring, t: t))
                        .opacity(mood == .idle ? 0.18 : 0.32 - Double(ring) * 0.08)
                        .blur(radius: size * 0.12)
                }
                UZeeLogo(size: size * 0.62, tile: true)
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            }
            .frame(width: size * 1.6, height: size * 1.6)
        }
        .accessibilityHidden(true)
    }

    private func scale(ring: Int, t: Double) -> CGFloat {
        let phase = Double(ring) * 0.9
        switch mood {
        case .idle: return 0.95
        case .listening: return 1.0 + 0.12 * CGFloat(sin(t * 2.4 + phase)) + CGFloat(ring) * 0.08
        case .thinking: return 1.0 + 0.05 * CGFloat(sin(t * 4 + phase)) + CGFloat(ring) * 0.06
        case .speaking: return 1.05 + 0.18 * CGFloat(abs(sin(t * 6 + phase))) + CGFloat(ring) * 0.1
        }
    }
}

/// Voice mode's big orb, like a voice assistant's blob: it glows and swells with your voice while listening,
/// spins while thinking, and pulses while UZee speaks (and the wallet sings along).
struct VoiceBlob: View {
    let mood: HelperOrb.Mood
    var size: CGFloat = 150
    /// The microphone level, 0…1, read every frame.
    var level: @Sendable () -> Float = { 0 }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSince(start)
            let loud = mood == .listening ? CGFloat(level()) : 0
            ZStack {
                glow(t: t, loud: loud)
                blob(t: t, loud: loud)
                if mood == .thinking {
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                        .frame(width: size * 0.86, height: size * 0.86)
                        .rotationEffect(.degrees(t * 400))
                }
                UZeeLogo(size: size * 0.5, singing: mood == .speaking)
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                    .scaleEffect(mood == .listening ? 1 + loud * 0.12 : 1)
            }
            .frame(width: size * 1.5, height: size * 1.5)
        }
        .accessibilityHidden(true)
    }

    private func glow(t: Double, loud: CGFloat) -> some View {
        let strength: CGFloat = switch mood {
        case .idle: 0.15
        case .listening: 0.3 + loud * 0.6
        case .thinking: 0.35
        case .speaking: 0.4 + 0.2 * CGFloat(abs(sin(t * 6)))
        }
        return Circle()
            .fill(RadialGradient(colors: [Color(red: 0.25, green: 0.75, blue: 0.95).opacity(strength), .clear],
                                 center: .center, startRadius: size * 0.3, endRadius: size * 0.75))
            .frame(width: size * 1.5, height: size * 1.5)
            .scaleEffect(1 + loud * 0.25)
    }

    private func blob(t: Double, loud: CGFloat) -> some View {
        let spin: Double = mood == .thinking ? 220 : mood == .idle ? 12 : 40
        let wobble: CGFloat = switch mood {
        case .idle: 0.015 * CGFloat(sin(t * 1.5))
        case .listening: 0.02 * CGFloat(sin(t * 2.4)) + loud * 0.28
        case .thinking: 0.03 * CGFloat(sin(t * 5))
        case .speaking: 0.08 * CGFloat(abs(sin(t * 6.5)))
        }
        return ZStack {
            Circle()
                .fill(AngularGradient(colors: HelperOrb.colors, center: .center, angle: .degrees(t * spin)))
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.45), .clear], center: UnitPoint(x: 0.35, y: 0.3),
                                     startRadius: 0, endRadius: size * 0.55))
        }
        .frame(width: size, height: size)
        .scaleEffect(x: 1 + wobble + 0.02 * CGFloat(sin(t * 3.1)), y: 1 + wobble + 0.02 * CGFloat(cos(t * 2.7)))
        .shadow(color: Color(red: 0.25, green: 0.55, blue: 0.98).opacity(0.35), radius: 18)
    }
}

/// The Ask UZee mic button: the smiling wallet singing into a studio mic, with a note floating up now and then.
struct SingingMic: View {
    var size: CGFloat = 44
    var active = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSince(start)
            ZStack(alignment: .bottomTrailing) {
                UZeeLogo(size: size, tile: true, singing: true)
                    .rotationEffect(.degrees(reduceMotion ? 0 : 4 * sin(t * 2.2)))
                StudioMic(size: size * 0.5)
                    .rotationEffect(.degrees(-28))
                    .offset(x: size * 0.1, y: size * 0.08)
                if !reduceMotion { note(t: t) }
            }
            .frame(width: size * 1.15, height: size * 1.1)
            .shadow(color: active ? Color(red: 0.25, green: 0.55, blue: 0.98).opacity(0.7) : .clear, radius: 10)
        }
        .accessibilityHidden(true)
    }

    /// A ♪ that drifts up and fades every couple of seconds.
    private func note(t: Double) -> some View {
        let cycle = (t / 2.4).truncatingRemainder(dividingBy: 1)
        return Text("♪")
            .font(.system(size: size * 0.32, weight: .bold))
            .foregroundStyle(Color(red: 0.98, green: 0.75, blue: 0.2))
            .opacity(cycle < 0.8 ? sin(cycle / 0.8 * .pi) : 0)
            .offset(x: -size * 0.95 - CGFloat(cycle) * size * 0.1, y: -size * 0.55 - CGFloat(cycle) * size * 0.35)
    }
}

/// A small studio microphone: a rounded grille head with a band, on a short handle.
struct StudioMic: View {
    var size: CGFloat = 22

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Capsule()
                    .fill(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                // Grille.
                VStack(spacing: size * 0.06) {
                    ForEach(0..<4, id: \.self) { _ in
                        Capsule().fill(Color.black.opacity(0.28)).frame(width: size * 0.3, height: size * 0.035)
                    }
                }
                .padding(.bottom, size * 0.12)
                Rectangle()
                    .fill(Color(red: 0.98, green: 0.75, blue: 0.2))
                    .frame(height: size * 0.08)
                    .offset(y: size * 0.16)
            }
            .frame(width: size * 0.46, height: size * 0.62)
            .clipShape(.capsule)
            .overlay(Capsule().stroke(.white.opacity(0.7), lineWidth: max(1, size * 0.03)))
            RoundedRectangle(cornerRadius: size * 0.05)
                .fill(LinearGradient(colors: [Color(white: 0.3), Color(white: 0.12)], startPoint: .leading, endPoint: .trailing))
                .frame(width: size * 0.16, height: size * 0.38)
        }
        .shadow(color: .black.opacity(0.3), radius: size * 0.06, y: size * 0.04)
    }
}
