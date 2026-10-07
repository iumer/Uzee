import SwiftUI

/// The UZee mark: a smiling "U" with two eyes and sparkles, the same drawing as the app icon (docs/brand/uzee-icon.svg).
/// Coordinates are in the icon's 1024-point space and scaled to the frame.
struct LogoU: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1024
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.move(to: p(330, 300))
        path.addLine(to: p(330, 560))
        path.addArc(tangent1End: p(330, 742), tangent2End: p(512, 742), radius: 182 * s)
        path.addArc(tangent1End: p(694, 742), tangent2End: p(694, 560), radius: 182 * s)
        path.addLine(to: p(694, 455))
        return path
    }
}

/// A four-point sparkle centred at (`x`, `y`) with radius `r`, in icon space.
struct LogoSparkle: Shape {
    var x: CGFloat
    var y: CGFloat
    var r: CGFloat

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1024
        let c = CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        let radius = r * s
        let k = radius * 0.16
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - radius))
        path.addCurve(to: CGPoint(x: c.x + radius, y: c.y), control1: CGPoint(x: c.x + k, y: c.y - k), control2: CGPoint(x: c.x + k, y: c.y - k))
        path.addCurve(to: CGPoint(x: c.x, y: c.y + radius), control1: CGPoint(x: c.x + k, y: c.y + k), control2: CGPoint(x: c.x + k, y: c.y + k))
        path.addCurve(to: CGPoint(x: c.x - radius, y: c.y), control1: CGPoint(x: c.x - k, y: c.y + k), control2: CGPoint(x: c.x - k, y: c.y + k))
        path.addCurve(to: CGPoint(x: c.x, y: c.y - radius), control1: CGPoint(x: c.x - k, y: c.y - k), control2: CGPoint(x: c.x - k, y: c.y - k))
        path.closeSubpath()
        return path
    }
}

/// A round eye centred at (`x`, `y`) with radius `r`, in icon space.
struct LogoEye: Shape {
    var x: CGFloat
    var y: CGFloat
    var r: CGFloat

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1024
        return Path(ellipseIn: CGRect(x: rect.minX + (x - r) * s, y: rect.minY + (y - r) * s, width: 2 * r * s, height: 2 * r * s))
    }
}

/// Animated UZee logo: the U draws itself in, its colours drift, the sparkles twinkle and the eyes blink.
/// With Reduce Motion on it is shown still.
struct UZeeLogo: View {
    var size: CGFloat = 64
    /// Draw the dark gradient tile behind the mark, like the app icon.
    var tile = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0

    static let colors: [Color] = [Color(red: 0.13, green: 0.83, blue: 0.93), Color(red: 0.65, green: 0.55, blue: 0.98),
                                  Color(red: 0.96, green: 0.45, blue: 0.71)]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                if tile { background(t) }
                mark(t)
            }
            .frame(width: size, height: size)
        }
        .onAppear {
            if reduceMotion { drawn = 1 } else { withAnimation(.easeOut(duration: 1.1)) { drawn = 1 } }
        }
        .accessibilityElement()
        .accessibilityLabel("UZee")
    }

    private func gradient(_ t: Double) -> LinearGradient {
        // The gradient's direction turns slowly, so the colours flow along the U.
        let angle = t * 0.6
        let dx = cos(angle) * 0.5, dy = sin(angle) * 0.5
        return LinearGradient(colors: Self.colors, startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy), endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }

    private func mark(_ t: Double) -> some View {
        let line = size * 150 / 1024
        let pulse = 0.55 + 0.25 * sin(t * 2)
        return ZStack {
            LogoU().trim(from: 0, to: drawn)
                .stroke(gradient(t), style: StrokeStyle(lineWidth: line, lineCap: .round))
                .blur(radius: size * 0.035)
                .opacity(pulse)
            LogoU().trim(from: 0, to: drawn)
                .stroke(gradient(t), style: StrokeStyle(lineWidth: line, lineCap: .round))
            eye(LogoEye(x: 448, y: 452, r: 44), t: t)
            eye(LogoEye(x: 576, y: 452, r: 44), t: t)
            sparkle(LogoSparkle(x: 694, y: 246, r: 124), t: t, phase: 0)
            sparkle(LogoSparkle(x: 838, y: 392, r: 52), t: t, phase: 1.7)
        }
    }

    /// Eyes pop in after the U and blink every few seconds (open and still with Reduce Motion).
    private func eye(_ shape: LogoEye, t: Double) -> some View {
        let period = 3.6, closing = 0.18
        let phase = t.truncatingRemainder(dividingBy: period)
        let blink = phase < closing ? 1 - 0.9 * sin(phase / closing * .pi) : 1
        let anchor = UnitPoint(x: shape.x / 1024, y: shape.y / 1024)
        let shown = max(0, min(1, (drawn - 0.6) / 0.4))
        return shape
            .fill(Color(red: 0.88, green: 0.97, blue: 1))
            .shadow(color: .white.opacity(0.6), radius: size * 0.02)
            .scaleEffect(x: shown, y: shown * CGFloat(blink), anchor: anchor)
            .opacity(Double(shown))
    }

    private func sparkle(_ shape: LogoSparkle, t: Double, phase: Double) -> some View {
        let twinkle = reduceMotion ? 1 : 0.82 + 0.18 * sin(t * 2.4 + phase)
        let anchor = UnitPoint(x: shape.x / 1024, y: shape.y / 1024)
        return shape
            .fill(LinearGradient(colors: [.white, Color(red: 0.77, green: 0.71, blue: 0.99)], startPoint: .top, endPoint: .bottom))
            .shadow(color: .white.opacity(0.7), radius: size * 0.03)
            .scaleEffect(drawn * CGFloat(twinkle), anchor: anchor)
            .rotationEffect(.degrees(reduceMotion ? 0 : sin(t * 0.8 + phase) * 8), anchor: anchor)
            .opacity(Double(drawn))
    }

    private func background(_ t: Double) -> some View {
        let drift = CGFloat(sin(t * 0.5)) * 0.08
        return RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(Color(red: 0.04, green: 0.04, blue: 0.12))
            .overlay {
                ZStack {
                    RadialGradient(colors: [Color(red: 0.49, green: 0.23, blue: 0.93).opacity(0.75), .clear],
                                   center: UnitPoint(x: 0.25 + drift, y: 0.22), startRadius: 0, endRadius: size * 0.55)
                    RadialGradient(colors: [Color(red: 0.15, green: 0.39, blue: 0.92).opacity(0.7), .clear],
                                   center: UnitPoint(x: 0.84 - drift, y: 0.88), startRadius: 0, endRadius: size * 0.6)
                    RadialGradient(colors: [Color(red: 0.93, green: 0.28, blue: 0.6).opacity(0.45), .clear],
                                   center: UnitPoint(x: 0.88, y: 0.16 + drift), startRadius: 0, endRadius: size * 0.42)
                }
                .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            }
    }
}

/// Shown for a moment at launch: the icon tile draws in, then fades into the app.
struct LaunchSplash: View {
    @Binding var isShowing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.12).ignoresSafeArea()
            VStack(spacing: 18) {
                UZeeLogo(size: 132, tile: true)
                    .shadow(color: Color(red: 0.49, green: 0.23, blue: 0.93).opacity(0.5), radius: 30)
                Text("UZee").font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(.white)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 500 : 1_400))
            withAnimation(.easeInOut(duration: 0.45)) { isShowing = false }
        }
        .accessibilityHidden(true)
    }
}
