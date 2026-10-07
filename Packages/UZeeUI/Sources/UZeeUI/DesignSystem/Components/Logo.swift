import SwiftUI

/// Animated UZee logo, "Wallet pal": the same drawing as the app icon (docs/brand/uzee-icon.svg).
/// The wallet pops in, two cards slide up out of it, the face appears, then the cards bob and the eyes blink.
/// With Reduce Motion on it is shown still. Drawn in the icon's 1024-point space and scaled to the frame.
struct UZeeLogo: View {
    var size: CGFloat = 64
    /// Draw the green tile behind the wallet, like the app icon.
    var tile = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 10 : context.date.timeIntervalSince(start)
            Canvas { gc, canvasSize in
                gc.scaleBy(x: canvasSize.width / 1024, y: canvasSize.height / 1024)
                draw(&gc, t: t, still: reduceMotion)
            }
            .frame(width: size, height: size)
        }
        .onAppear { start = .now }
        .accessibilityElement()
        .accessibilityLabel("UZee")
    }

    private static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    private static func ease(_ x: Double) -> CGFloat {
        let c = max(0, min(1, x))
        return CGFloat(1 - pow(1 - c, 3))
    }

    private func draw(_ gc: inout GraphicsContext, t: Double, still: Bool) {
        let h = Self.hex
        let pop = Self.ease(t / 0.5)
        let cards = Self.ease((t - 0.3) / 0.6)
        let face = Self.ease((t - 0.6) / 0.45)
        let bob = still ? 0 : CGFloat(sin(t * 1.8)) * 7

        if tile {
            let tilePath = Path(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024), cornerRadius: 230, style: .continuous)
            gc.fill(tilePath, with: .linearGradient(Gradient(colors: [h(0x43E3A6), h(0x0B9467)]),
                                                    startPoint: .zero, endPoint: CGPoint(x: 0, y: 1024)))
            gc.fill(tilePath, with: .radialGradient(Gradient(colors: [.white.opacity(0.32), .white.opacity(0)]),
                                                    center: CGPoint(x: 225, y: 123), startRadius: 0, endRadius: 770))
        }

        // Cards rise from behind the wallet, then bob gently.
        let lift = (1 - cards) * 170
        card(&gc, center: CGPoint(x: 482, y: 339 + lift + bob), angle: -10, colors: [h(0xFDE68A), h(0xFBBF24), h(0xF59E0B)], visible: cards)
        card(&gc, center: CGPoint(x: 552, y: 361 + lift - bob * 0.7), angle: 6, colors: [h(0x93C5FD), h(0x60A5FA), h(0x3B82F6)], visible: cards)

        // Wallet body pops in from its centre.
        var wallet = gc
        let k = 0.6 + 0.4 * pop
        wallet.opacity = Double(pop)
        wallet.translateBy(x: 512, y: 588)
        wallet.scaleBy(x: k, y: k)
        wallet.translateBy(x: -512, y: -588)

        let bodyRect = CGRect(x: 200, y: 368, width: 624, height: 440)
        let bodyPath = Path(roundedRect: bodyRect, cornerRadius: 104, style: .continuous)
        wallet.drawLayer { layer in
            layer.addFilter(.shadow(color: h(0x053B2A).opacity(0.38), radius: 30, x: 0, y: 28))
            layer.fill(bodyPath, with: .linearGradient(Gradient(colors: [.white, h(0xE3F6EE)]),
                                                       startPoint: CGPoint(x: 0, y: 368), endPoint: CGPoint(x: 0, y: 808)))
        }
        wallet.stroke(Path(roundedRect: bodyRect.insetBy(dx: 3, dy: 3), cornerRadius: 101, style: .continuous),
                      with: .color(.white.opacity(0.9)), lineWidth: 6)
        wallet.stroke(Path(roundedRect: CGRect(x: 236, y: 404, width: 552, height: 368), cornerRadius: 76, style: .continuous),
                      with: .color(h(0xA7E3CB).opacity(0.9)), style: StrokeStyle(lineWidth: 7, lineCap: .round, dash: [2, 22]))

        // Clasp and button.
        let clasp = Path(roundedRect: CGRect(x: 640, y: 524, width: 222, height: 136), cornerRadius: 68, style: .continuous)
        wallet.drawLayer { layer in
            layer.addFilter(.shadow(color: h(0x053B2A).opacity(0.25), radius: 12, x: 0, y: 10))
            layer.fill(clasp, with: .linearGradient(Gradient(colors: [h(0xE7FBF2), h(0xBDEFD9)]),
                                                    startPoint: CGPoint(x: 0, y: 524), endPoint: CGPoint(x: 0, y: 660)))
        }
        wallet.fill(Path(ellipseIn: CGRect(x: 682, y: 562, width: 60, height: 60)),
                    with: .radialGradient(Gradient(colors: [h(0x34D399), h(0x047857)]), center: CGPoint(x: 703, y: 580), startRadius: 0, endRadius: 48))
        wallet.fill(Path(ellipseIn: CGRect(x: 698, y: 571, width: 18, height: 18)), with: .color(.white.opacity(0.7)))

        // Face: cheeks, blinking eyes and a smile that draws itself.
        var faceLayer = wallet
        faceLayer.opacity = Double(pop) * Double(face)
        let ink = h(0x0A4D38)
        for cx: CGFloat in [338, 582] {
            faceLayer.fill(Path(ellipseIn: CGRect(x: cx - 34, y: 592, width: 68, height: 40)), with: .color(h(0x6EE7B7).opacity(0.55)))
        }
        let open = blink(t, still: still) * face
        for cx: CGFloat in [398, 516] {
            let eyeHeight = 80 * open
            faceLayer.fill(Path(ellipseIn: CGRect(x: cx - 40, y: 540 - eyeHeight / 2, width: 80, height: eyeHeight)), with: .color(ink))
            if open > 0.6 {
                faceLayer.fill(Path(ellipseIn: CGRect(x: cx - 2, y: 514, width: 24, height: 24)), with: .color(.white.opacity(0.9)))
            }
        }
        var smile = Path()
        smile.move(to: CGPoint(x: 372, y: 644))
        smile.addQuadCurve(to: CGPoint(x: 542, y: 644), control: CGPoint(x: 457, y: 722))
        faceLayer.stroke(smile.trimmedPath(from: 0, to: face), with: .color(ink), style: StrokeStyle(lineWidth: 40, lineCap: .round))
    }

    /// 1 when the eyes are open; dips towards 0.1 for a quick blink every few seconds.
    private func blink(_ t: Double, still: Bool) -> CGFloat {
        guard !still, t > 1.2 else { return 1 }
        let period = 3.6, closing = 0.18
        let phase = (t - 1.2).truncatingRemainder(dividingBy: period)
        return phase < closing ? CGFloat(1 - 0.9 * sin(phase / closing * .pi)) : 1
    }

    private func card(_ gc: inout GraphicsContext, center: CGPoint, angle: Double, colors: [Color], visible: CGFloat) {
        var c = gc
        c.opacity = Double(visible)
        c.translateBy(x: center.x, y: center.y)
        c.rotate(by: .degrees(angle))
        let rect = CGRect(x: -200, y: -125, width: 400, height: 250)
        let shape = Path(roundedRect: rect, cornerRadius: 40, style: .continuous)
        c.drawLayer { layer in
            layer.addFilter(.shadow(color: Self.hex(0x053B2A).opacity(0.25), radius: 12, x: 0, y: 10))
            layer.fill(shape, with: .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: -200, y: -125), endPoint: CGPoint(x: 200, y: 125)))
        }
        var inside = c
        inside.clip(to: shape)
        inside.fill(Path(CGRect(x: -200, y: -63, width: 400, height: 44)), with: .color(.black.opacity(0.1)))
        inside.fill(Path(roundedRect: CGRect(x: -156, y: 7, width: 70, height: 52), cornerRadius: 12), with: .color(Self.hex(0xFFF7D6).opacity(0.85)))
        c.stroke(Path(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: 38, style: .continuous), with: .color(.white.opacity(0.45)), lineWidth: 4)
    }
}

/// Shown for a moment at launch: the wallet tile animates in, then fades into the app.
struct LaunchSplash: View {
    @Binding var isShowing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.24, blue: 0.18), Color(red: 0.02, green: 0.08, blue: 0.06)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                UZeeLogo(size: 132, tile: true)
                    .shadow(color: Color(red: 0.2, green: 0.83, blue: 0.6).opacity(0.45), radius: 30)
                Text("UZee").font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(.white)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 500 : 1_500))
            withAnimation(.easeInOut(duration: 0.45)) { isShowing = false }
        }
        .accessibilityHidden(true)
    }
}
