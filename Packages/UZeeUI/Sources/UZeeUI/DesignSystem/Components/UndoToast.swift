import SwiftUI

/// Shows one toast at a time above the tab bar, e.g. "Saved · Undo" for 5 s (DESIGN_SYSTEM §10, AUD-13).
@MainActor
@Observable
public final class ToastCenter {
    public struct Toast: Identifiable, Equatable {
        public let id = UUID()
        public let message: String
        public let hasUndo: Bool

        public static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
    }

    public private(set) var current: Toast?
    /// Seconds a toast stays up. Five by the design rules; tests may shorten it.
    public var duration: Duration = .seconds(5)
    private var undo: (() -> Void)?
    private var dismissTask: Task<Void, Never>?

    public init() {}

    public func show(_ message: String, undo: (() -> Void)? = nil) {
        dismissTask?.cancel()
        current = Toast(message: message, hasUndo: undo != nil)
        self.undo = undo
        AccessibilityNotification.Announcement(undo == nil ? message : "\(message). Undo available").post()
        scheduleDismiss()
    }

    public func performUndo() {
        let action = undo
        undo = nil
        action?()
        current = Toast(message: "Undone", hasUndo: false)
        scheduleDismiss(after: .seconds(2))
    }

    public func dismiss() {
        dismissTask?.cancel()
        current = nil
        undo = nil
    }

    /// While VoiceOver focus is on the toast it stays up (DESIGN_SYSTEM §11).
    func hold(_ focused: Bool) {
        if focused { dismissTask?.cancel() } else { scheduleDismiss() }
    }

    private func scheduleDismiss(after delay: Duration? = nil) {
        dismissTask?.cancel()
        let wait = delay ?? duration
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.current = nil
            self?.undo = nil
        }
    }
}

struct UndoToastView: View {
    let toast: ToastCenter.Toast
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: UZSpacing.l) {
            Text(toast.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .accessibilityIdentifier("toast.message")
            if toast.hasUndo {
                Button("Undo", action: onUndo)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .systemBlue).mix(with: .white, by: 0.25))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("toast.undo")
            }
        }
        .padding(.horizontal, UZSpacing.xxxl)
        .frame(minHeight: 48)
        .glassEffect(.regular.tint(.black.opacity(0.6)), in: .capsule)
    }
}

struct ToastOverlay: ViewModifier {
    let center: ToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var focused: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            ZStack {
                if let toast = center.current {
                    UndoToastView(toast: toast) { center.performUndo() }
                        .accessibilityFocused($focused)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .id(toast.id)
                }
            }
            // Above the bottom bar and the floating UZee.
            .padding(.bottom, 140)
            .animation(UZMotion.pick(UZMotion.toast, reduceMotion: reduceMotion), value: center.current)
            .onChange(of: focused) { _, isFocused in center.hold(isFocused) }
        }
    }
}

extension View {
    /// Hosts the toast for this subtree. Apply once at the root.
    public func toastOverlay(_ center: ToastCenter) -> some View {
        modifier(ToastOverlay(center: center))
    }
}

/// Closes the keyboard, then runs `work` on the next turn, so the last digit typed reaches the form before it
/// saves (owner, 2026-10-19: typing fast and tapping Save could drop it, 4567 → 456).
/// A second tap while one is waiting is ignored, so a double tap can't save twice.
@MainActor
func afterTyping(_ work: @escaping @MainActor () -> Void) {
    guard !TypingGate.waiting else { return }
    TypingGate.waiting = true
    // The box being typed in hands over exactly what it shows, in case its last keystroke hasn't reached the form.
    if let field = TypingGate.focusedField() {
        field.sendActions(for: .editingChanged)
        NotificationCenter.default.post(name: UITextField.textDidChangeNotification, object: field)
    }
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(150))
        work()
        // Keep ignoring taps a moment longer, while the sheet closes.
        try? await Task.sleep(for: .milliseconds(350))
        TypingGate.waiting = false
    }
}

@MainActor
enum TypingGate {
    static var waiting = false
    fileprivate static weak var found: UIResponder?

    /// The text box being typed in, if any.
    static func focusedField() -> UITextField? {
        found = nil
        UIApplication.shared.sendAction(#selector(UIResponder.uzeeReportFocus(_:)), to: nil, from: nil, for: nil)
        return found as? UITextField
    }
}

extension UIResponder {
    @objc fileprivate func uzeeReportFocus(_ sender: Any?) {
        MainActor.assumeIsolated { TypingGate.found = self }
    }
}
