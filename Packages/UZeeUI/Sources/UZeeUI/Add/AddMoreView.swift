import PhotosUI
import SwiftUI
import UZeeCore

/// Add › More (round 3 mockup Q): what the main Add screen leaves out because it's used less often.
/// Note, pending, tags and a receipt photo, plus the other kinds of entry.
struct AddMoreView: View {
    @Bindable var session: AppSession
    @Binding var note: String
    @Binding var isPending: Bool
    @Binding var tagIDs: Set<UUID>
    let hasReceipt: Bool
    /// False while editing: a saved entry keeps its kind.
    let canChangeKind: Bool
    let onPhoto: @MainActor (Data?) -> Void
    let onRefund: @MainActor () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        Form {
            Section {
                TextField("Add a note", text: $note, axis: .vertical)
                    .accessibilityIdentifier("add.note")
                Toggle("Pending (not in balance yet)", isOn: $isPending)
                    .accessibilityIdentifier("add.pending")
            }
            Section {
                if session.tags.isEmpty {
                    Text("No tags yet. Make them in Settings › Tags.").foregroundStyle(UZColor.label2)
                }
                ForEach(session.tags) { tag in
                    Button {
                        if tagIDs.contains(tag.id) { tagIDs.remove(tag.id) } else { tagIDs.insert(tag.id) }
                    } label: {
                        HStack {
                            Text("#" + tag.name).foregroundStyle(UZColor.label)
                            Spacer()
                            if tagIDs.contains(tag.id) { Image(systemName: "checkmark").foregroundStyle(UZColor.tint) }
                        }
                    }
                    .accessibilityAddTraits(tagIDs.contains(tag.id) ? .isSelected : [])
                    .accessibilityIdentifier("add.tag.\(tag.name)")
                }
            } header: {
                Text("Tags")
            }
            Section {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(hasReceipt ? "Replace the receipt photo" : "Attach a receipt from Photos", systemImage: "photo")
                }
                .accessibilityIdentifier("add.attachPhoto")
            } header: {
                Text("Receipt photo")
            } footer: {
                Text("UZee reads it on this iPhone and fills in what it can.")
            }
            if canChangeKind {
                Section {
                    NavigationLink {
                        LoanPersonList(session: session)
                    } label: {
                        kindRow("Lent / borrowed", "Money between you and a person", systemImage: "arrow.left.arrow.right")
                    }
                    .accessibilityIdentifier("add.more.loan")
                    Button {
                        onRefund()
                        dismiss()
                    } label: {
                        kindRow("Refund", "Money back from a shop", systemImage: "arrow.uturn.backward")
                    }
                    .accessibilityIdentifier("add.more.refund")
                    NavigationLink {
                        FixBalanceList(session: session)
                    } label: {
                        kindRow("Fix a balance", "Make an account match the bank", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityIdentifier("add.more.fix")
                } header: {
                    Text("Other kinds")
                }
            }
        }
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                onPhoto(data)
                dismiss()
            }
        }
    }

    private func kindRow(_ title: String, _ detail: String, systemImage: String) -> some View {
        HStack(spacing: UZSpacing.l) {
            Image(systemName: systemImage).font(.body.weight(.semibold)).foregroundStyle(UZColor.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                Text(title).foregroundStyle(UZColor.label)
                Text(detail).font(.footnote).foregroundStyle(UZColor.label2)
            }
        }
    }
}

/// Add › More › Lent / borrowed: pick the person, then the usual lend or borrow sheet.
private struct LoanPersonList: View {
    @Bindable var session: AppSession
    @State private var chosen: Chosen?

    private struct Chosen: Identifiable { let id: UUID }

    var body: some View {
        List {
            if session.people.others.isEmpty {
                Text("No people yet. Add someone in People first.").foregroundStyle(UZColor.label2)
            }
            ForEach(session.people.others) { person in
                Button(person.name) { chosen = Chosen(id: person.id) }
                    .foregroundStyle(UZColor.label)
                    .accessibilityIdentifier("add.loan.\(person.name)")
            }
        }
        .navigationTitle("Who with?")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $chosen) { LoanSheet(session: session, personID: $0.id, direction: .lent) }
    }
}

/// Add › More › Fix a balance: pick the account, then type what the bank shows.
private struct FixBalanceList: View {
    @Bindable var session: AppSession
    @State private var chosen: Account?

    var body: some View {
        List {
            ForEach(session.ledger.activeAccounts) { account in
                Button {
                    chosen = account
                } label: {
                    HStack {
                        Text(account.name).foregroundStyle(UZColor.label)
                        Spacer()
                        Text(MoneyFormatter.string(session.ledger.balance(of: account))).foregroundStyle(UZColor.label2).monospacedDigit()
                    }
                }
                .accessibilityIdentifier("add.fix.\(account.name)")
            }
        }
        .navigationTitle("Which account?")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $chosen) { ReconcileSheet(session: session, account: $0) }
    }
}
