import SwiftUI

/// The UZee helper's face: the wallet logo in a soft glow that breathes while listening, ripples while
/// speaking and turns slowly while thinking. Still with Reduce Motion.
struct HelperOrb: View {
    enum Mood: Equatable { case idle, listening, thinking, speaking }

    let mood: Mood
    var size: CGFloat = 120
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private static let colors: [Color] = [Color(red: 0.20, green: 0.78, blue: 0.55), Color(red: 0.25, green: 0.55, blue: 0.98),
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
