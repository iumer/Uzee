// UZee · Built by iUmer Farooq
// Copyright (c) 2026 iUmer Farooq. All rights reserved. See LICENSE.

import SwiftUI
import UZeeCore

/// One To pay / To receive item (owner, 2026-11-03): the total, what's paid and what's left, then every payment with
/// its date, time and account. Tap a payment to fix it; one saved as spending changes its Activity entry too, and an
/// edit made in Activity shows here.
struct PaymentTodoDetailView: View {
    @Bindable var session: AppSession
    let todoID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var payments: [TodoPayment] = []
    @State private var offer: (payment: UUID, transaction: UUID, amount: Money)?
    @State private var paying = false
    @State private var editingTodo = false
    @State private var editingPayment: TodoPayment?
    @State private var confirmDelete = false

    private var todo: PaymentTodo? { session.paymentTodos.first { $0.id == todoID } }

    var body: some View {
        Group {
            if let todo {
                List {
                    summary(todo)
                    if let offer { offerSection(offer) }
                    history(todo)
                }
            } else {
                EmptyStateView("Deleted", systemImage: "trash", description: "It's no longer on your list.")
            }
        }
        .navigationTitle(todo?.name ?? "Payment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if todo != nil {
                Menu {
                    Button("Edit name, amount or date", systemImage: "pencil") { editingTodo = true }
                        .accessibilityIdentifier("todo.edit")
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        .accessibilityIdentifier("todo.delete")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("todo.more")
            }
        }
        .onAppear { session.hidesFloatingButtons = true; load() }
        .onDisappear { session.hidesFloatingButtons = false }
        // Activity edits, payments and undos all reload the session; the history follows.
        .onChange(of: session.paymentTodos) { load() }
        .onChange(of: session.transactions) { load() }
        .sheet(isPresented: $paying, onDismiss: load) {
            if let todo { PayTodoSheet(session: session, todo: todo, showsManage: false) }
        }
        .sheet(isPresented: $editingTodo) {
            if let todo { PaymentTodoForm(session: session, editing: todo) }
        }
        .sheet(item: $editingPayment, onDismiss: load) { payment in
            if let todo { TodoPaymentSheet(session: session, todo: todo, payment: payment) }
        }
        .confirmationDialog("Delete \(todo?.name ?? "")?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let todo {
                    ToPayView.delete(todo, session: session)
                    dismiss()
                }
            }
        } message: {
            Text("Entries it made stay in Activity. You can undo this.")
        }
        .accessibilityIdentifier("screen.paymentTodo")
    }

    private func load() {
        payments = (try? session.calendar.payments.list(todoID)) ?? []
        offer = (try? session.calendar.payments.suggestedLink(todoID)).flatMap { $0 }.map { ($0.0, $0.1, $0.2) }
    }

    private func receiving(_ todo: PaymentTodo) -> Bool { todo.direction == .receive }

    @ViewBuilder
    private func summary(_ todo: PaymentTodo) -> some View {
        Section {
            VStack(alignment: .leading, spacing: UZSpacing.s) {
                Text(MoneyFormatter.string(todo.amount)).font(.largeTitle.bold()).monospacedDigit()
                let fraction = todo.amount.minorUnits > 0 ? min(1, Double(todo.paid.minorUnits) / Double(todo.amount.minorUnits)) : 0
                ProgressBarView(fraction: fraction, tint: UZColor.positive,
                                label: "\(MoneyFormatter.string(todo.paid)) of \(MoneyFormatter.string(todo.amount))")
            }
            .padding(.vertical, UZSpacing.xs)
            LabeledContent(receiving(todo) ? "Received" : "Paid", value: MoneyFormatter.string(todo.paid))
                .accessibilityIdentifier("todo.paid")
            LabeledContent(receiving(todo) ? "Still to come" : "Left to pay", value: MoneyFormatter.string(todo.remaining))
                .accessibilityIdentifier("todo.left")
            if let due = todo.dueDate {
                LabeledContent("Due", value: due.formatted(date: .abbreviated, time: .omitted))
            }
            if !todo.isDone {
                Button { paying = true } label: {
                    Label(receiving(todo) ? "Received some or all" : "Pay some or all", systemImage: "checkmark.circle.fill")
                        .fontWeight(.semibold)
                }
                .accessibilityIdentifier("todo.pay")
            } else {
                Label(receiving(todo) ? "All received" : "All paid", systemImage: "checkmark.seal.fill").foregroundStyle(UZColor.positive)
            }
        }
    }

    /// "Use Rs 400,000 from Activity?": an earlier payment kept as a total, and the one entry it most likely was.
    private func offerSection(_ offer: (payment: UUID, transaction: UUID, amount: Money)) -> some View {
        Section {
            let entry = session.transactions.first { $0.id == offer.transaction }
            VStack(alignment: .leading, spacing: UZSpacing.s) {
                Text("Activity has \(entry?.payeeName ?? "an entry") for \(MoneyFormatter.string(offer.amount))"
                     + (entry.map { " on \($0.occurredAt.formatted(date: .abbreviated, time: .omitted))" } ?? "") + ".")
                    .font(.subheadline)
                Text("Use it for the earlier payment? Then fixing it in Activity changes what's paid here.")
                    .font(.footnote).foregroundStyle(UZColor.label2)
                Button("Use \(MoneyFormatter.string(offer.amount)) from Activity") {
                    if session.perform("Couldn't link it. Try again.", { try session.calendar.payments.link(offer.payment, offer.transaction) }) {
                        session.toasts.show("Now \(MoneyFormatter.string(todo?.paid ?? offer.amount)) paid")
                        load()
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("todo.useOffer")
            }
            .padding(.vertical, UZSpacing.xs)
        }
    }

    @ViewBuilder
    private func history(_ todo: PaymentTodo) -> some View {
        Section {
            if payments.isEmpty {
                Text(receiving(todo) ? "Nothing received yet." : "Nothing paid yet.").foregroundStyle(UZColor.label2)
            }
            ForEach(payments) { payment in
                Button { editingPayment = payment } label: { paymentRow(payment) }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(payment) }
                    }
                    .accessibilityIdentifier("todo.payment.\(MarkPaidSheet.plain(payment.amount))")
            }
        } header: {
            Text("History")
        } footer: {
            if !payments.isEmpty {
                Text("Tap one to fix the amount, date or account. Swipe left to delete it.")
            }
        }
    }

    private func paymentRow(_ payment: TodoPayment) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(payment.isEarlier ? "Earlier payments" : payment.paidAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(UZColor.label)
                Text(where_(payment)).font(.footnote).foregroundStyle(UZColor.label2)
            }
            Spacer()
            Text(MoneyFormatter.string(payment.amount)).monospacedDigit().fontWeight(.semibold).foregroundStyle(UZColor.label)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(UZColor.label3)
        }
        .contentShape(.rect)
    }

    private func where_(_ payment: TodoPayment) -> String {
        if payment.isEarlier { return "Paid before UZee kept a history" }
        guard let account = session.ledger.account(payment.accountID) else { return "Not added to an account" }
        return payment.transactionID == nil ? account.name : "\(account.name) · in Activity"
    }

    /// A payment saved as spending goes with its entry (Undo brings both back); one kept only here is set aside.
    private func delete(_ payment: TodoPayment) {
        if let id = payment.transactionID, let entry = session.transactions.first(where: { $0.id == id }) {
            session.delete(entry)
        } else if session.perform("Couldn't delete it. Try again.", { try session.calendar.payments.delete(payment.id) }) {
            session.toasts.show("Payment deleted") {
                _ = session.perform("Couldn't undo. Try again.", { try session.calendar.payments.restore(payment.id) })
            }
        }
        load()
    }
}

/// Fix one payment: amount, date and time, account. A payment saved as spending or income changes that entry too.
struct TodoPaymentSheet: View {
    @Bindable var session: AppSession
    let todo: PaymentTodo
    let payment: TodoPayment
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var date = Date()
    @State private var accountID: UUID?
    @State private var problem: String?
    @State private var loaded = false

    private var entry: MoneyTransaction? { payment.transactionID.flatMap { id in session.transactions.first { $0.id == id } } }
    /// The entry can follow the edit when it's in the to-do's currency; otherwise only this record changes.
    private var editsEntry: Bool { entry.map { $0.amount.currency == todo.amount.currency } ?? false }
    private var receiving: Bool { todo.direction == .receive }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(todo.amount.currency.symbol).foregroundStyle(UZColor.label2)
                        TextField("0", text: $amountText).keyboardType(.decimalPad).monospacedDigit()
                            .accessibilityIdentifier("todoPayment.amount")
                    }
                    DatePicker("Date", selection: $date)
                        .accessibilityIdentifier("todoPayment.date")
                    if let entry, editsEntry {
                        Picker(receiving ? "Received into" : "Paid from", selection: $accountID) {
                            ForEach(session.ledger.activeAccounts.filter { $0.currency == entry.amount.currency }) {
                                Text($0.name).tag(UUID?.some($0.id))
                            }
                        }
                        .accessibilityIdentifier("todoPayment.account")
                    } else if entry == nil {
                        LabeledContent("Account", value: "Not added to an account")
                    }
                } header: {
                    Text(todo.name)
                } footer: {
                    if entry != nil && editsEntry {
                        Text("This is also the \(receiving ? "income" : "spending") entry in Activity; it changes there too, and so does the account's balance.")
                    } else if entry != nil {
                        Text("The entry in Activity is in another currency. This changes the amount counted here; open the entry in Activity to change it there.")
                    } else {
                        Text("Kept only here; no account changes.")
                    }
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(UZColor.negative) }
                }
            }
            .navigationTitle("Edit payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { afterTyping(save) }.fontWeight(.semibold).accessibilityIdentifier("todoPayment.save")
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                amountText = MarkPaidSheet.plain(payment.amount)
                date = payment.paidAt
                accountID = payment.accountID
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let amount = try? AmountParser.parse(amountText, currency: todo.amount.currency), amount.minorUnits > 0 else {
            problem = "Enter the amount."
            return
        }
        // Everything else paid, plus this one, can't go past the total.
        let others = todo.paid.minorUnits - payment.amount.minorUnits
        if others + amount.minorUnits > todo.amount.minorUnits {
            let room = Money(minorUnits: max(0, todo.amount.minorUnits - others), currency: todo.amount.currency)
            problem = "That's more than the \(MoneyFormatter.string(room)) this payment can be."
            return
        }
        if let entry, editsEntry {
            var updated = entry
            // Not split: your share is the whole amount, so budgets and reports follow the fix too.
            if entry.myShare == entry.amount { updated.myShare = amount }
            updated.amount = amount
            updated.occurredAt = date
            updated.localDate = LocalDate(date, in: .current)
            for index in updated.legs.indices where updated.legs[index].role == .main {
                let sign: Int64 = updated.legs[index].amount.minorUnits < 0 ? -1 : 1
                updated.legs[index].amount = Money(minorUnits: sign * amount.minorUnits, currency: amount.currency)
                if let accountID { updated.legs[index].accountID = accountID }
            }
            guard session.save(updated, isNew: false) else {
                problem = "Couldn't save. Nothing was changed. Try again."
                return
            }
        }
        var changed = payment
        changed.amount = amount
        changed.paidAt = date
        if entry == nil { changed.accountID = nil } else if editsEntry { changed.accountID = accountID }
        if session.perform("Couldn't save. Try again.", { try session.calendar.payments.update(changed) }) {
            session.toasts.show("Payment saved")
            dismiss()
        }
    }
}
