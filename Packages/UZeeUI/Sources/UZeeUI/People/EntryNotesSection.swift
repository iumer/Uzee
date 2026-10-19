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

/// A note as a chat bubble with its date and time, used on loan and person-entry pages.
struct NoteBubble: View {
    let text: String
    let time: Date?

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 4) {
                Text(text)
                    .padding(.horizontal, UZSpacing.l).padding(.vertical, UZSpacing.m)
                    .background(UZColor.tint.opacity(0.15), in: .rect(cornerRadius: 18))
                    .textSelection(.enabled)
                if let time {
                    Text(time.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(UZColor.label2)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("note.bubble")
    }
}

/// The "Add a note" bar pinned to the bottom of a loan or person-entry page.
struct NoteComposer: View {
    @Binding var draft: String
    var typing: FocusState<Bool>.Binding
    let send: () -> Void

    var body: some View {
        HStack(spacing: UZSpacing.m) {
            TextField("Add a note", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused(typing)
                .padding(.horizontal, UZSpacing.l).padding(.vertical, UZSpacing.m)
                .background(UZColor.card, in: .rect(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(typing.wrappedValue ? UZColor.tint : UZColor.separator, lineWidth: 1))
                .contentShape(.rect)
                .onTapGesture { typing.wrappedValue = true }
                .accessibilityIdentifier("note.field")
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Add note")
            .accessibilityIdentifier("note.send")
        }
        .padding(.horizontal, UZSpacing.xxl).padding(.vertical, UZSpacing.m)
        .background(.bar)
    }
}
