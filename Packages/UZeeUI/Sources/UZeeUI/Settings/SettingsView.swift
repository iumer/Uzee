import SwiftUI

/// Settings (SCR-04). M1 holds sample data and app info; the other sections arrive with their features.
struct SettingsView: View {
    @Bindable var session: AppSession
    @State private var confirmingRemove = false

    var body: some View {
        List {
            Section {
                if session.isSampleMode {
                    Button(role: .destructive) {
                        confirmingRemove = true
                    } label: {
                        SettingsLabel("Remove sample data", symbol: "trash", color: Color(uiColor: .systemRed))
                    }
                    .accessibilityIdentifier("settings.sampleOff")
                } else {
                    Button {
                        session.turnOnSampleData()
                    } label: {
                        SettingsLabel("Explore with sample data", symbol: "sparkles", color: Color(uiColor: .systemOrange))
                    }
                    .accessibilityIdentifier("settings.sampleOn")
                }
            } header: {
                Text("Sample data")
            } footer: {
                Text("Sample data shows UZee with the October example. It is kept apart from your own entries and removed in one step.")
            }

            Section("About") {
                LabeledContent {
                    Text(session.info.displayVersion).monospacedDigit()
                } label: {
                    SettingsLabel("Version", symbol: "info", color: Color(uiColor: .systemGray))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Version \(session.info.displayVersion)")
                .accessibilityIdentifier("settings.version")

                LabeledContent {
                    Text(databaseText)
                        .foregroundStyle(session.isDatabaseReady ? UZColor.positive : UZColor.negative)
                } label: {
                    SettingsLabel("Database", symbol: "cylinder.split.1x2", color: Color(uiColor: .systemGreen))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(databaseText)
                .accessibilityIdentifier("settings.database")
            }

            #if DEBUG
            Section {
                NavigationLink(value: Route.componentGallery) {
                    SettingsLabel("Design components", symbol: "paintpalette", color: Color(uiColor: .systemIndigo))
                }
                .accessibilityIdentifier("settings.gallery")
            } header: {
                Text("Developer")
            } footer: {
                Text("Shown in development builds only.")
            }
            #endif
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove sample data?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove sample data", role: .destructive) { session.removeSampleData() }
        } message: {
            Text("Only the sample entries are removed. Anything you added yourself stays.")
        }
    }

    var databaseText: String {
        session.isDatabaseReady ? "Database ready" : "Database could not open"
    }
}

/// Settings row label: 30 pt rounded icon tile in a system colour, then the title.
struct SettingsLabel: View {
    let title: String
    let symbol: String
    let color: Color
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 30

    init(_ title: String, symbol: String, color: Color) {
        self.title = title
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(color, in: .rect(cornerRadius: UZRadius.badge, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}
