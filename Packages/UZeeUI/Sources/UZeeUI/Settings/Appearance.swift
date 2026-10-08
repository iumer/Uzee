import SwiftUI
import UIKit

/// Light, dark or follow the iPhone (SET-03). Applied to every window of the app, so sheets, alerts and the
/// lock curtain follow it too.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let defaultsKey = "uzee.appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var style: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    static var current: Appearance {
        Appearance(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
    }

    /// Sets the style on every window now, including ones opened by the system such as share sheets' hosts.
    @MainActor
    static func apply(_ appearance: Appearance = .current) {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows { window.overrideUserInterfaceStyle = appearance.style }
        }
    }
}

/// Settings row: System / Light / Dark.
struct AppearancePicker: View {
    @AppStorage(Appearance.defaultsKey) private var appearance: Appearance = .system

    var body: some View {
        Picker(selection: $appearance) {
            ForEach(Appearance.allCases) { option in
                Label(option.title, systemImage: option.symbol).tag(option)
            }
        } label: {
            SettingsLabel("Appearance", symbol: "circle.lefthalf.filled", color: Color(uiColor: .systemIndigo))
        }
        .onChange(of: appearance, initial: true) { _, value in
            withAnimation(.easeInOut(duration: 0.3)) { Appearance.apply(value) }
        }
        .accessibilityIdentifier("settings.appearance")
    }
}
