import SwiftUI
import UIKit
import UZeeCore

/// One loan (owner, 2026-10-15: "when I tap that 150k entry inside Mom"): when it was added, what's left, the
/// payments, and dated notes kept like a chat, newest at the bottom, with a box to add another.
struct LoanDetailView: View {
    @Bindable var session: AppSession
    let loanID: UUID
    @State private var sheet: PersonSheet?
    @State private var draft = ""
    @FocusState private var typing: Bool
    @State private var editing = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    private var loan: Loan? { session.people.loans.first { $0.id == loanID } }

    var body: some View {
        Group {
            if let loan {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: UZSpacing.xl) {
                            summary(loan)
                            if !loan.payments.isEmpty { paymentsCard(loan) }
                            notesSection(loan)
                        }
                        .padding(.horizontal, UZSpacing.xxl)
                        .padding(.bottom, UZSpacing.xl)
                    }
                    .onChange(of: loan.noteLog.count) {
                        withAnimation(.snappy) { proxy.scrollTo("notes.end", anchor: .bottom) }
                    }
                }
                .safeAreaInset(edge: .bottom) { NoteComposer(draft: $draft, typing: $typing, send: send) }
            } else {
                EmptyStateView("Not found", systemImage: "doc.questionmark", description: "This loan was removed.")
            }
        }
        .background(UZColor.bg)
        .navigationTitle(title)
        .onAppear { session.hidesFloatingButtons = true }
        .onDisappear { session.hidesFloatingButtons = false }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let loan {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Change the amount, date, account or note (owner, 2026-10-19).
                    Button("Edit") { editing = true }
                        .accessibilityIdentifier("loan.edit")
                    Menu {
                        let status = LoanCalculator.status(loan)
                        if status == .open || status == .partiallyPaid {
                            Button(loan.direction == .lent ? "They paid you" : "You paid back", systemImage: "arrow.uturn.backward") {
                                sheet = .repay(loan.id)
                            }
                        }
                        Button("Due date and interest", systemImage: "calendar") { sheet = .due(loan.id) }
                        Button(loan.writtenOffAt == nil ? "Write off" : "Undo write-off", systemImage: "xmark.seal") {
                            let writeOff = loan.writtenOffAt == nil
                            if session.perform("Couldn't change the loan. Try again.", { try session.peopleClient.setWrittenOff(writeOff, loan.id) }) {
                                session.toasts.show(writeOff ? "Written off" : "Write-off undone")
                            }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                            .accessibilityIdentifier("loan.delete")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                    .accessibilityIdentifier("loan.more")
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let loan { LoanEditSheet(session: session, loan: loan) }
        }
        .confirmationDialog("Delete this loan?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let loan, session.deleteLoan(loan) { dismiss() }
            }
            .accessibilityIdentifier("loan.confirmDelete")
        } message: {
            Text("The balance with them updates now. You can undo it.")
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .repay(let id): RepaymentSheet(session: session, loanID: id)
            case .due(let id): LoanTermsSheet(session: session, loanID: id)
            default: EmptyView()
            }
        }
    }

    private var title: String {
        guard let loan else { return "Loan" }
        let name = loan.personID.flatMap { session.people.person($0)?.name } ?? loan.institution ?? ""
        return loan.direction == .lent ? "Lent to \(name)" : "Borrowed from \(name)"
    }

    private func summary(_ loan: Loan) -> some View {
        let status = LoanCalculator.status(loan)
        let today = LocalDate(Date(), in: .current)
        let left = LoanCalculator.outstanding(loan)
        return UZCard(tint: loan.direction == .lent ? UZColor.positive : UZColor.negative) {
            VStack(alignment: .leading, spacing: UZSpacing.m) {
                Text(loan.direction == .lent ? "You lent" : "You borrowed").font(.subheadline).foregroundStyle(UZColor.label2)
                Text(MoneyFormatter.string(loan.principal)).font(.largeTitle.bold()).monospacedDigit()
                Divider()
                LabeledContent("Date", value: loan.startDate.startDate(in: .current).formatted(date: .long, time: .omitted))
                if let created = loan.createdAt {
                    LabeledContent("Added to UZee", value: created.formatted(date: .abbreviated, time: .shortened))
                }
                if let due = loan.dueDate { LabeledContent("Due", value: due.listTitle(today: today)) }
                LabeledContent("Status", value: status.name)
                if status == .open || status == .partiallyPaid {
                    LabeledContent("Left") {
                        Text(MoneyFormatter.string(left)).monospacedDigit().fontWeight(.semibold)
                            .foregroundStyle(loan.direction == .lent ? UZColor.positive : UZColor.negative)
                    }
                }
                let interest = LoanCalculator.interest(loan, asOf: today)
                if !interest.isZero { LabeledContent("Interest so far", value: MoneyFormatter.string(interest)) }
                if loan.isOpeningBalance { LabeledContent("Kind", value: "Record only, no account money moved") }
                if let transaction = session.transactions.first(where: { $0.id == loan.transactionID }),
                   let leg = transaction.legs.first(where: { $0.role == .main }) {
                    LabeledContent(loan.direction == .lent ? "From" : "Into", value: session.ledger.account(leg.accountID)?.name ?? "Account")
                }
                if let note = loan.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    LabeledContent("For", value: note)
                }
            }
            .font(.subheadline)
        }
        .accessibilityIdentifier("loan.summary")
    }

    private func paymentsCard(_ loan: Loan) -> some View {
        let today = LocalDate(Date(), in: .current)
        return VStack(alignment: .leading, spacing: UZSpacing.m) {
            SectionHeader("Payments")
            UZCard {
                VStack(spacing: 0) {
                    ForEach(loan.payments, id: \.id) { payment in
                        HStack {
                            Text(payment.paidOn.listTitle(today: today))
                            Spacer()
                            Text("−" + MoneyFormatter.string(payment.amount)).monospacedDigit().fontWeight(.semibold)
                        }
                        .padding(.vertical, UZSpacing.m)
                        if payment.id != loan.payments.last?.id { Divider() }
                    }
                }
            }
        }
    }

    /// Notes as chat bubbles, each with its date and time. The old single note, if any, comes first.
    private func notesSection(_ loan: Loan) -> some View {
        VStack(alignment: .leading, spacing: UZSpacing.m) {
            SectionHeader("Notes")
            if loan.noteLog.isEmpty {
                Text("No notes yet. Write one below, like \"Will pay back after Eid\".")
                    .font(.footnote).foregroundStyle(UZColor.label2)
            }
            ForEach(loan.noteLog) { note in
                NoteBubble(text: note.text, time: note.createdAt)
                    .contextMenu {
                        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = note.text }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            _ = session.perform("Couldn't delete the note. Try again.", { try session.peopleClient.deleteLoanNote(note.id) })
                        }
                    }
            }
            Color.clear.frame(height: 1).id("notes.end")
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if session.perform("Couldn't add the note. Try again.", { try session.peopleClient.addLoanNote(text, loanID) }) {
            draft = ""
            typing = false
        }
    }
}
