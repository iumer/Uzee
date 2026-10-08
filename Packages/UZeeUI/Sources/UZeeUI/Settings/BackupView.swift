import SwiftUI
import UniformTypeIdentifiers
import UZeeCore

/// Settings › Backup and restore (DATA-02, US-11): a password-protected file with everything, including
/// receipts, saved wherever you like (Files, iCloud Drive, AirDrop); restore checks it before replacing anything.
struct BackupView: View {
    @Bindable var session: AppSession

    @State private var password = ""
    @State private var confirm = ""
    @State private var working = false
    @State private var file: URL?
    @State private var problem: String?

    @State private var importing = false
    @State private var restoreData: Data?
    @State private var restorePassword = ""
    @State private var summary: BackupSummary?
    @State private var confirmRestore = false

    var body: some View {
        Form {
            Section {
                SecureField("Password (8 or more characters)", text: $password)
                    .textContentType(.newPassword)
                    .accessibilityIdentifier("backup.password")
                SecureField("Same password again", text: $confirm)
                    .textContentType(.newPassword)
                    .accessibilityIdentifier("backup.confirm")
                if let file {
                    ShareLink(item: file) { Label("Save or share the backup", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("backup.share")
                } else {
                    Button {
                        make()
                    } label: {
                        HStack {
                            Label("Make backup", systemImage: "lock.doc")
                            if working { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(working || password.count < BackupProblem.minimumPasswordLength || password != confirm)
                    .accessibilityIdentifier("backup.make")
                }
            } header: {
                Text("Back up")
            } footer: {
                Text("Everything in UZee, with receipts, in one encrypted file. Keep the password safe: without it the backup can't be opened, by you or anyone else.")
            }
            Section {
                Button { importing = true } label: { Label("Restore from a backup…", systemImage: "arrow.counterclockwise") }
                    .accessibilityIdentifier("backup.restore")
                if restoreData != nil {
                    SecureField("Backup password", text: $restorePassword)
                        .accessibilityIdentifier("backup.restorePassword")
                    Button("Check backup") { check() }
                        .disabled(working || restorePassword.isEmpty)
                }
                if let summary {
                    VStack(alignment: .leading, spacing: UZSpacing.xs) {
                        Text("Made \(summary.createdAt.formatted(date: .abbreviated, time: .shortened)) · UZee \(summary.appVersion)")
                            .font(.subheadline.weight(.semibold))
                        Text("\(summary.transactions) transactions, \(summary.accounts) accounts, \(summary.receipts) receipts")
                            .font(.subheadline).foregroundStyle(UZColor.label2)
                    }
                    Button("Replace everything with this backup", role: .destructive) { confirmRestore = true }
                        .accessibilityIdentifier("backup.replace")
                }
            } header: {
                Text("Restore")
            } footer: {
                Text("Restoring replaces what's in UZee now. A copy of your current data is kept on this iPhone first.")
            }
            if let problem {
                Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(UZColor.negative) }
                    .accessibilityIdentifier("backup.problem")
            }
        }
        .navigationTitle("Backup and restore")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            problem = nil
            summary = nil
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            restoreData = try? Data(contentsOf: url)
            if restoreData == nil { problem = "Couldn't open that file." }
        }
        .confirmationDialog("Replace everything in UZee with this backup?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Replace everything", role: .destructive) { restore() }
        } message: {
            Text("Your current data is copied aside first.")
        }
        .onChange(of: password) { file = nil }
    }

    private func make() {
        working = true
        problem = nil
        let backup = session.backup, secret = password
        Task {
            let result = await Task.detached { Result { try backup.makeBackup(secret) } }.value
            working = false
            switch result {
            case .success(let url): file = url
            case .failure(let error): problem = (error as? BackupProblem)?.message ?? BackupProblem.failed.message
            }
        }
    }

    private func check() {
        guard let data = restoreData else { return }
        working = true
        problem = nil
        let backup = session.backup, secret = restorePassword
        Task {
            let result = await Task.detached { Result { try backup.inspect(data, secret) } }.value
            working = false
            switch result {
            case .success(let found): summary = found
            case .failure(let error): problem = (error as? BackupProblem)?.message ?? BackupProblem.failed.message
            }
        }
    }

    private func restore() {
        guard let data = restoreData else { return }
        working = true
        let backup = session.backup, secret = restorePassword
        Task {
            let result = await Task.detached { Result { try backup.restore(data, secret) } }.value
            working = false
            switch result {
            case .success:
                session.reloadAfterRestore()
                restoreData = nil
                summary = nil
                restorePassword = ""
                session.toasts.show("Backup restored")
            case .failure(let error):
                problem = (error as? BackupProblem)?.message ?? BackupProblem.failed.message
            }
        }
    }
}
