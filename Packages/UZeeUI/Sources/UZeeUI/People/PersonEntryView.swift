import SwiftUI
import UZeeCore

/// Which page an entry opens on. Every list (Activity, a person, a group, accounts, budget, bills, search) goes
/// through here, so the same entry always opens the same way (owner, 2026-10-19).
struct EntryDestination: View {
    @Bindable var session: AppSession
    let transactionID: UUID

    var body: some View {
        switch session.entryPage(for: transactionID) {
        case .loan(let loan): LoanDetailView(session: session, loanID: loan)
        case .person: PersonEntryView(session: session, transactionID: transactionID)
        case .plain: TransactionDetailView(session: session, transactionID: transactionID)
        }
    }
}

/// An expense shared with someone, or a settle-up, on the People-style page a loan has (owner, 2026-10-19):
/// what it was, who paid and who owes, then notes like a chat with a box at the bottom. Edit reopens the form
/// it was made with.
struct PersonEntryView: View {
    @Bindable var session: AppSession
    let transactionID: UUID
    @State private var notes: [LoanNote] = []
    @State private var draft = ""
    @State private var confirmDelete = false
    @FocusState private var typing: Bool
    @Environment(\.dismiss) private var dismiss

    private var transaction: MoneyTransaction? { session.transactions.first { $0.id == transactionID } }

    var body: some View {
        Group {
            if let transaction {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: UZSpacing.xl) {
                            summary(transaction)
                            notesSection
                        }
                        .padding(.horizontal, UZSpacing.xxl)
                        .padding(.bottom, UZSpacing.xl)
                    }
                    .onChange(of: notes.count) {
                        withAnimation(.snappy) { proxy.scrollTo("entry.notes.end", anchor: .bottom) }
                    }
                }
                .safeAreaInset(edge: .bottom) { NoteComposer(draft: $draft, typing: $typing, send: send) }
            } else {
                EmptyStateView("Deleted", systemImage: "trash", description: "It no longer appears in your lists and totals.")
            }
        }
        .background(UZColor.bg)
        .navigationTitle(transaction.map(title) ?? "Entry")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { session.hidesFloatingButtons = true }
        .onDisappear { session.hidesFloatingButtons = false }
        .task(id: transactionID) { load() }
        .toolbar {
            if let transaction {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if session.isSharedExpense(transaction) {
                        Button("Edit") { session.openAdd(.edit(transaction)) }
                            .accessibilityIdentifier("entry.edit")
                    }
                    Menu {
                        if session.isSharedExpense(transaction) {
                            Button("Add again today", systemImage: "plus.square.on.square") { session.openAdd(.repeatOf(transaction)) }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                            .accessibilityIdentifier("entry.delete")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                    .accessibilityIdentifier("entry.more")
                }
            }
        }
        .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let transaction {
                    session.delete(transaction)
                    dismiss()
                }
            }
            .accessibilityIdentifier("entry.confirmDelete")
        } message: {
            Text("Balances update now. You can undo it, and it stays in Recently Deleted for 30 days.")
        }
    }

    private func title(_ transaction: MoneyTransaction) -> String {
        if transaction.kind == .settlement { return "Settle up" }
        return transaction.payeeName ?? "Shared expense"
    }

    @ViewBuilder
    private func summary(_ transaction: MoneyTransaction) -> some View {
        let model = PeopleModel(session: session)
        let ledger = session.ledger
        if transaction.kind == .settlement, let settlement = Settlement.from(transaction) {
            let name = session.people.person(settlement.personID)?.name ?? "Them"
            UZCard(tint: settlement.amount.isNegative ? UZColor.positive : UZColor.negative) {
                VStack(alignment: .leading, spacing: UZSpacing.m) {
                    Text(settlement.amount.isNegative ? "\(name) paid you" : "You paid \(name)").font(.subheadline).foregroundStyle(UZColor.label2)
                    Text(MoneyFormatter.string(SplitText.magnitude(settlement.amount))).font(.largeTitle.bold()).monospacedDigit()
                    Divider()
                    common(transaction, ledger: ledger)
                }
                .font(.subheadline)
            }
            .accessibilityIdentifier("entry.summary")
        } else {
            let split = session.people.split(for: transaction.id)
            let isIncome = SpendingRules.countsAsIncome(transaction.kind)
            let others = split?.people.filter { $0 != model.me } ?? []
            let effect = split.flatMap { split in
                others.count == 1 ? model.effect(of: split, isIncome: isIncome, with: others[0]) : model.effect(of: split, isIncome: isIncome)
            }
            UZCard(tint: effect.map { $0.isZero ? nil : SplitText.color($0) } ?? nil) {
                VStack(alignment: .leading, spacing: UZSpacing.m) {
                    Text(transaction.payeeName ?? "Shared expense").font(.subheadline).foregroundStyle(UZColor.label2)
                    Text(MoneyFormatter.string(transaction.amount)).font(.largeTitle.bold()).monospacedDigit()
                    if let effect, !effect.isZero {
                        Text(owesLine(effect, other: others.count == 1 ? model.name(others[0]) : nil))
                            .font(.headline).foregroundStyle(SplitText.color(effect))
                            .accessibilityIdentifier("entry.owes")
                    }
                    Divider()
                    if let split {
                        ForEach(split.payers, id: \.personID) { payer in
                            LabeledContent(isIncome ? "Received by \(model.name(payer.personID))" : "Paid by \(model.name(payer.personID))",
                                           value: MoneyFormatter.string(payer.amount))
                        }
                        ForEach(split.shares, id: \.personID) { share in
                            LabeledContent(share.personID == model.me ? "Your share" : "\(model.name(share.personID))'s share",
                                           value: MoneyFormatter.string(share.share))
                        }
                        if let group = session.people.group(split.groupID) {
                            NavigationLink(value: Route.group(group.id)) { LabeledContent("Group", value: group.name) }
                        }
                    }
                    if let path = ledger.categoryPath(transaction.categoryID) { LabeledContent("Category", value: path) }
                    common(transaction, ledger: ledger)
                }
                .font(.subheadline)
            }
            .accessibilityIdentifier("entry.summary")
        }
    }

    /// Date, the account it moved through (or that none did), and the note typed when it was added.
    @ViewBuilder
    private func common(_ transaction: MoneyTransaction, ledger: LedgerSnapshot) -> some View {
        LabeledContent("Date", value: transaction.occurredAt.formatted(date: .long, time: .omitted))
        if let leg = transaction.legs.first(where: { $0.role == .main }) {
            LabeledContent(transaction.kind == .settlement && leg.amount.minorUnits > 0 ? "Into" : "Paid from",
                           value: ledger.account(leg.accountID)?.name ?? "Account")
        } else {
            LabeledContent("Account", value: "None, no money left your accounts")
        }
        if let note = transaction.note, !note.isEmpty { LabeledContent("Note", value: note) }
    }

    private func owesLine(_ effect: Money, other: String?) -> String {
        let amount = MoneyFormatter.string(SplitText.magnitude(effect))
        if let other { return effect.isNegative ? "You owe \(other) \(amount)" : "\(other) owes you \(amount)" }
        return effect.isNegative ? "You owe \(amount)" : "You are owed \(amount)"
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: UZSpacing.m) {
            SectionHeader("Notes")
            if notes.isEmpty {
                Text("No notes yet. Write one below, like \"Paid my half in cash\".")
                    .font(.footnote).foregroundStyle(UZColor.label2)
            }
            ForEach(notes) { note in
                NoteBubble(text: note.text, time: note.createdAt)
                    .contextMenu {
                        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = note.text }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            if session.perform("Couldn't delete the note. Try again.", { try session.peopleClient.deleteEntryNote(note.id) }) { load() }
                        }
                    }
            }
            Color.clear.frame(height: 1).id("entry.notes.end")
        }
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
