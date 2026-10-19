import SwiftUI
import UZeeCore

/// Notes on a shared expense or a payment with a person, as chat bubbles with date and time, the same as a
/// loan's (owner, 2026-10-19: "I can add comments on a loan but not on this").
struct EntryNotesSection: View {
    @Bindable var session: AppSession
    let transactionID: UUID
    @State private var notes: [LoanNote] = []
    @State private var draft = ""
    @FocusState private var typing: Bool

    var body: some View {
        Section {
            if notes.isEmpty {
                Text("No notes yet. Write one, like \"Paid my half in cash\".")
                    .font(.footnote).foregroundStyle(UZColor.label2)
            }
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.text).textSelection(.enabled)
                    Text(note.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(UZColor.label2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("entry.note")
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        if session.perform("Couldn't delete the note. Try again.", { try session.peopleClient.deleteEntryNote(note.id) }) { load() }
                    }
                }
                .contextMenu {
                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = note.text }
                }
            }
            HStack(spacing: UZSpacing.m) {
                TextField("Add a note", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($typing)
                    .accessibilityIdentifier("entry.noteField")
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 28))
                }
                .buttonStyle(.borderless)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add note")
                .accessibilityIdentifier("entry.noteSend")
            }
        } header: {
            Text("Notes")
        }
        .task(id: transactionID) { load() }
    }

    private func load() {
        notes = (try? session.peopleClient.entryNotes(transactionID)) ?? []
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if session.perform("Couldn't add the note. Try again.", { try session.peopleClient.addEntryNote(text, transactionID) }) {
            draft = ""
            typing = false
            load()
        }
    }
}
