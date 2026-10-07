import SwiftUI

/// Press feedback for tappable cards and rows: scale 0.96 with a spring, none under Reduce Motion.
public struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : UZMotion.press, value: configuration.isPressed)
    }
}

/// Full-width 50 pt capsule primary action used in sheets. Shows progress while busy.
public struct PrimaryButton: View {
    let title: String
    let isBusy: Bool
    let action: () -> Void

    public init(_ title: String, isBusy: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isBusy = isBusy
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isBusy ? 0 : 1)
                if isBusy { ProgressView() }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .disabled(isBusy)
    }
}
