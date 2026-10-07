import SwiftUI

/// Shared level for bars and rings: under, near (≥ warning threshold) or over (DESIGN_SYSTEM §11).
public enum ProgressLevel: Sendable, Equatable {
    case under, near, over

    public init(fraction: Double, warnAt: Double = 0.85) {
        self = fraction > 1 ? .over : (fraction >= warnAt ? .near : .under)
    }

    var color: Color {
        switch self {
        case .under: UZColor.tint
        case .near: UZColor.warning
        case .over: UZColor.negative
        }
    }
}

/// 8 pt capsule bar (category budget, salary split, kameti).
public struct ProgressBarView: View {
    let fraction: Double
    let tint: Color?
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter label: spoken value, e.g. "Personal, 9,800 of 8,600 rupees, over by 1,200".
    public init(fraction: Double, tint: Color? = nil, label: String) {
        self.fraction = fraction
        self.tint = tint
        self.label = label
    }

    public var body: some View {
        let level = ProgressLevel(fraction: fraction)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(UZColor.fill)
                Capsule()
                    .fill(level == .under ? (tint ?? level.color) : level.color)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 8)
        .animation(UZMotion.pick(UZMotion.value, reduceMotion: reduceMotion), value: fraction)
        .accessibilityElement()
        .accessibilityLabel(label)
    }
}

/// Ring that shows what is left (AUD-36). Over budget: full ring in negative with "Over".
public struct ProgressRingView<Center: View>: View {
    let remaining: Double
    let label: String
    let center: Center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter remaining: share left, 1 = nothing spent, below 0 = over.
    public init(remaining: Double, label: String, @ViewBuilder center: () -> Center) {
        self.remaining = remaining
        self.label = label
        self.center = center()
    }

    public var body: some View {
        let level = ProgressLevel(fraction: 1 - remaining)
        ZStack {
            Circle().stroke(UZColor.fill, lineWidth: 10)
            Circle()
                .trim(from: 0, to: level == .over ? 1 : min(max(remaining, 0), 1))
                .stroke(level.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .animation(UZMotion.pick(UZMotion.value, reduceMotion: reduceMotion), value: remaining)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}
