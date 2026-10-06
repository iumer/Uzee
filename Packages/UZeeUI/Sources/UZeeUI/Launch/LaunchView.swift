import SwiftUI
import UZeeCore

/// M0 placeholder screen: app name, version and database status.
/// Replaced by the tab bar in M1.
public struct LaunchView: View {
    public enum DatabaseStatus: Equatable, Sendable {
        case ready
        case failed
    }

    let info: AppInfo
    let status: DatabaseStatus

    public init(info: AppInfo, status: DatabaseStatus) {
        self.info = info
        self.status = status
    }

    public var body: some View {
        VStack(spacing: 12) {
            Text("UZee")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("launch.title")
            Text(info.displayVersion)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("launch.version")
            Label(statusText, systemImage: status == .ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(status == .ready ? Color.green : Color.orange)
                // One accessibility element, so VoiceOver reads the status once and tests find one match.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(statusText)
                .accessibilityIdentifier("launch.database")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.groupedBackground)
    }

    var statusText: String {
        switch status {
        case .ready: "Database ready"
        case .failed: "Database could not open"
        }
    }
}

#Preview {
    LaunchView(info: AppInfo(marketingVersion: "0.0.1", buildNumber: "1"), status: .ready)
}

extension Color {
    /// systemGroupedBackground on iOS; falls back on platforms without UIKit (package tests on macOS).
    static var groupedBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color.gray.opacity(0.1)
        #endif
    }
}
