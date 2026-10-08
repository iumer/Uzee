import LocalAuthentication
import SwiftUI
import UZeeCore

/// Optional Face ID lock (SEC-01): UZee locks when it goes to the background and opens with Face ID,
/// Touch ID or the iPhone passcode.
enum AppLock {
    static let key = "uzee.faceIDLock"
    static let timeoutKey = "uzee.lockTimeout"

    /// Seconds away before UZee locks again: immediately, after 1 minute or after 5 minutes.
    static var timeout: TimeInterval { UserDefaults.standard.double(forKey: timeoutKey) }

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) && !ProcessInfo.processInfo.arguments.contains("-uzee-in-memory") }

    /// "Face ID", "Touch ID" or "Passcode", for labels.
    static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    static var canLock: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    /// Asks for Face ID (falling back to the passcode); true when the owner is confirmed.
    @MainActor
    static func unlock(reason: String = "Unlock UZee") async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Not now"
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// Covers the app while it is locked.
struct LockScreen: View {
    var showsButton = true
    var unlock: () -> Void = {}

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.24, blue: 0.18), Color(red: 0.02, green: 0.08, blue: 0.06)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: UZSpacing.xxl) {
                UZeeLogo(size: 96, tile: true)
                Text(showsButton ? "UZee is locked" : "UZee").font(.title2.bold()).foregroundStyle(.white)
                if showsButton {
                    Button(action: unlock) {
                        Label("Unlock with \(AppLock.methodName)", systemImage: AppLock.methodName == "Touch ID" ? "touchid" : "faceid")
                            .font(.headline).padding(.horizontal, UZSpacing.l).padding(.vertical, UZSpacing.s)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("lock.unlock")
                }
            }
        }
    }
}

/// Settings › Privacy: the lock switch, tried once so turning it on proves it works.
struct LockToggle: View {
    @AppStorage(AppLock.key) private var isOn = false
    @AppStorage(AppLock.timeoutKey) private var timeout: Double = 0

    var body: some View {
        toggle
        if isOn {
            Picker("Lock", selection: $timeout) {
                Text("Immediately").tag(0.0)
                Text("After 1 minute").tag(60.0)
                Text("After 5 minutes").tag(300.0)
            }
            .accessibilityIdentifier("settings.lockTimeout")
        }
    }

    private var toggle: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { wanted in
            if !wanted { isOn = false; return }
            Task { @MainActor in isOn = await AppLock.unlock(reason: "Turn on the lock for UZee") }
        })) {
            SettingsLabel("Lock with \(AppLock.methodName)", symbol: AppLock.methodName == "Touch ID" ? "touchid" : "faceid",
                          color: Color(uiColor: .systemGreen))
        }
        .disabled(!AppLock.canLock && !isOn)
        .accessibilityIdentifier("settings.lock")
    }
}

/// Settings › Export (EXP-01): every transaction as a CSV file to share, save to Files or open in Numbers.
struct ExportView: View {
    @Bindable var session: AppSession
    @State private var file: URL?
    @State private var problem: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Transactions", value: "\(session.transactions.count)")
                LabeledContent("Accounts", value: "\(session.ledger.accounts.count)")
            } footer: {
                Text("One row per account movement: date, type, account, amount (minus is money out), currency, category, payee, note. Opens in Numbers, Excel or Google Sheets.")
            }
            Section {
                if let file {
                    ShareLink(item: file) {
                        Label("Share CSV file", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("export.share")
                } else if let problem {
                    Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(UZColor.negative)
                } else {
                    ProgressView()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Export")
        .task { write() }
    }

    private func write() {
        let csv = CSVExport.transactions(session.transactions, ledger: session.ledger)
        let name = "UZee transactions \(session.today.description).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try Data(csv.utf8).write(to: url, options: [.atomic, .completeFileProtection])
            file = url
        } catch {
            problem = "Couldn't make the file. Try again."
        }
    }
}
