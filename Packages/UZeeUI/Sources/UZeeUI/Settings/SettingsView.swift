import SwiftUI
import UZeeCore

/// Settings (SCR-04): money setup, import and voice, privacy and export, sample data.
struct SettingsView: View {
    @Bindable var session: AppSession
    @State private var confirmingRemove = false

    var body: some View {
        List {
            Section("Money") {
                NavigationLink(value: Route.accounts) {
                    SettingsLabel("Accounts", symbol: "building.columns", color: Color(uiColor: .systemBlue))
                }
                .accessibilityIdentifier("settings.accounts")
                NavigationLink(value: Route.exchangeRate) {
                    HStack {
                        SettingsLabel("Exchange rate", symbol: "dollarsign.arrow.circlepath", color: Color(uiColor: .systemGreen))
                        Spacer()
                        Text("$1 = Rs \(ExchangeRate.display(session.ledger.rate(for: .usd)))").foregroundStyle(UZColor.label2)
                    }
                }
                .accessibilityIdentifier("settings.rate")
                NavigationLink(value: Route.categories) {
                    SettingsLabel("Categories", symbol: "square.grid.2x2", color: Color(uiColor: .systemOrange))
                }
                .accessibilityIdentifier("settings.categories")
                NavigationLink(value: Route.tags) {
                    SettingsLabel("Tags", symbol: "number", color: Color(uiColor: .systemTeal))
                }
                .accessibilityIdentifier("settings.tags")
                NavigationLink {
                    ReminderSettingsView(session: session)
                } label: {
                    SettingsLabel("Reminders", symbol: "bell.badge", color: Color(uiColor: .systemRed))
                }
                .accessibilityIdentifier("settings.reminders")
                NavigationLink(value: Route.recentlyDeleted) {
                    SettingsLabel("Recently Deleted", symbol: "trash", color: Color(uiColor: .systemGray))
                }
                .accessibilityIdentifier("settings.deleted")
            }
            Section {
                Button {
                    session.openImport()
                } label: {
                    SettingsLabel("Import bank statement", symbol: "square.and.arrow.down", color: Color(uiColor: .systemIndigo))
                }
                .accessibilityIdentifier("settings.import")
                NavigationLink {
                    SiriVoiceView(session: session)
                } label: {
                    SettingsLabel("Siri & voice", symbol: "waveform", color: Color(uiColor: .systemPurple))
                }
                .accessibilityIdentifier("settings.voice")
            } header: {
                Text("Import and voice")
            }
            Section {
                LockToggle()
                NavigationLink {
                    ExportView(session: session)
                } label: {
                    SettingsLabel("Export to CSV", symbol: "square.and.arrow.up", color: Color(uiColor: .systemBlue))
                }
                .accessibilityIdentifier("settings.export")
                NavigationLink {
                    BackupView(session: session)
                } label: {
                    SettingsLabel("Backup and restore", symbol: "externaldrive.badge.timemachine", color: Color(uiColor: .systemTeal))
                }
                .accessibilityIdentifier("settings.backup")
            } header: {
                Text("Privacy and data")
            } footer: {
                Text("Your data stays on this iPhone. The lock asks for \(AppLock.methodName) each time you come back to UZee.")
            }
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
            // Only for development runs started with -uzee-developer, never on the owner's phone.
            if ProcessInfo.processInfo.arguments.contains("-uzee-developer") {
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
