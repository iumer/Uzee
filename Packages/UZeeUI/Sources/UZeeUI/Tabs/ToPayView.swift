import SwiftUI
import UZeeCore

/// Plan › To pay (owner, 2026-10-15): a to-do list of payments, not tied to a month. At the top, what you have
/// (from the accounts you pick), what's still to pay, and what's left after paying it all. Each payment is paid
/// in full or in parts ("Kameti 20,000: paid 10,000, 10,000 left").
struct ToPayView: View {
    @Bindable var session: AppSession
    @State private var editing: PaymentTodo?
    @State private var adding = false
    @State private var paying: PaymentTodo?
    @State private var pickingAccounts = false
    @State private var showsPaid = false

    static let excludedKey = "uzee.toPay.excludedAccounts"

    /// The accounts counted in "You have": all in totals, minus the ones switched off here.
    private var counted: [Account] {
        let excluded = Set(UserDefaults.standard.stringArray(forKey: Self.excludedKey) ?? [])
        return session.ledger.activeAccounts.filter { $0.includeInTotals && !excluded.contains($0.id.uuidString) }
    }

    private var have: Money {
        let ledger = session.ledger
        let balances = Dictionary(uniqueKeysWithValues: counted.map { ($0.id, ledger.balance(of: $0)) })
        return (try? BalanceCalculator.available(accounts: counted, balances: balances, base: ledger.base, rates: ledger.rates))
            ?? .zero(ledger.base)
    }

    var body: some View {
        let todos = session.paymentTodos
        let open = todos.filter { !$0.isDone }
        let paid = todos.filter(\.isDone)
        let have = self.have
        let summary = PaymentTodo.summary(todos, have: have, rates: session.ledger.rates)
        ScrollView {
            VStack(alignment: .leading, spacing: UZSpacing.xl) {
                PlanSwitch(session: session)
                UZCard {
                    VStack(alignment: .leading, spacing: UZSpacing.m) {
                        Button { pickingAccounts = true } label: {
                            HStack {
                                Text("You have").foregroundStyle(UZColor.label2)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(UZColor.label3)
                                Spacer()
                                Text(MoneyFormatter.string(have)).font(.title3.weight(.semibold)).monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("toPay.have")
                        HStack {
                            Text("To pay").foregroundStyle(UZColor.label2)
                            Spacer()
                            Text(MoneyFormatter.string(summary.toPay)).font(.title3.weight(.semibold)).monospacedDigit()
                        }
                        Divider()
                        HStack(alignment: .firstTextBaseline) {
                            Text(summary.left.isNegative ? "Short by" : "Left after paying").font(.title3.weight(.semibold))
                            Spacer()
                            Text(MoneyFormatter.string(Money(minorUnits: summary.left.minorUnits.magnitudeClamped, currency: summary.left.currency)))
                                .font(.title2.weight(.bold)).monospacedDigit()
                                .foregroundStyle(summary.left.isNegative ? UZColor.negative : UZColor.positive)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("toPay.left")
                    }
                }
                VStack(alignment: .leading, spacing: UZSpacing.m) {
                    SectionHeader("To pay")
                    UZCard {
                        VStack(spacing: 0) {
                            if open.isEmpty {
                                Text("Nothing to pay. Add rent, kameti, fuel, money for home…")
                                    .font(.subheadline).foregroundStyle(UZColor.label2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, UZSpacing.m)
                            }
                            ForEach(open) { todo in
                                row(todo)
                                Divider()
                            }
                            Button { adding = true } label: {
                                Label("Add a payment", systemImage: "plus.circle.fill").frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, UZSpacing.l)
                            .accessibilityIdentifier("toPay.add")
                        }
                    }
                }
                if !paid.isEmpty {
                    DisclosureGroup(isExpanded: $showsPaid) {
                        VStack(spacing: 0) {
                            ForEach(paid) { todo in
                                row(todo)
                                if todo.id != paid.last?.id { Divider() }
                            }
                        }
                    } label: {
                        Text("Paid (\(paid.count))").font(.subheadline.weight(.semibold))
                    }
                    .padding(UZSpacing.xxl)
                    .background(UZColor.card, in: .rect(cornerRadius: UZRadius.card))
                }
                Text("Tap a payment when you pay it, in full or a part. Left after paying is what you have minus everything still to pay.")
                    .font(.caption).foregroundStyle(UZColor.label2)
            }
            .padding(.horizontal, UZSpacing.xxl)
            .padding(.bottom, 96)
        }
        .background(UZColor.bg)
        .navigationTitle("Plan")
        .sheet(isPresented: $adding) { PaymentTodoForm(session: session, editing: nil) }
        .sheet(item: $editing) { PaymentTodoForm(session: session, editing: $0) }
        .sheet(item: $paying) { PayTodoSheet(session: session, todo: $0) }
        .sheet(isPresented: $pickingAccounts) { HaveAccountsSheet(session: session) }
        .accessibilityIdentifier("screen.toPay")
    }

    private func row(_ todo: PaymentTodo) -> some View {
        let fraction = todo.amount.minorUnits > 0 ? Double(todo.paid.minorUnits) / Double(todo.amount.minorUnits) : 0
        return Button { if todo.isDone { editing = todo } else { paying = todo } } label: {
            VStack(alignment: .leading, spacing: UZSpacing.s) {
                HStack {
                    Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(todo.isDone ? UZColor.positive : UZColor.label3)
                    Text(todo.name).strikethrough(todo.isDone).foregroundStyle(UZColor.label)
                    Spacer()
                    Text(MoneyFormatter.string(todo.isDone ? todo.amount : todo.remaining)).monospacedDigit().fontWeight(.semibold)
                        .foregroundStyle(todo.isDone ? UZColor.label2 : UZColor.label)
                }
                if !todo.isDone, todo.paid.minorUnits > 0 {
                    ProgressBarView(fraction: fraction, tint: UZColor.positive,
                                    label: "\(MoneyFormatter.string(todo.paid)) paid of \(MoneyFormatter.string(todo.amount))")
                    Text("Paid \(MoneyFormatter.string(todo.paid)) of \(MoneyFormatter.string(todo.amount)) · \(MoneyFormatter.string(todo.remaining)) left")
                        .font(.footnote).foregroundStyle(UZColor.label2)
                }
            }
            .padding(.vertical, UZSpacing.l)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !todo.isDone {
                Button("Pay", systemImage: "checkmark.circle") { paying = todo }
            }
            Button("Edit", systemImage: "pencil") { editing = todo }
            Button("Delete", systemImage: "trash", role: .destructive) {
                _ = session.perform("Couldn't delete it. Try again.", { try session.calendar.deletePaymentTodo(todo.id) })
            }
        }
        .accessibilityIdentifier("toPay.row.\(todo.name)")
    }
}

/// New or edited payment: a name and the amount, in any currency.
struct PaymentTodoForm: View {
    @Bindable var session: AppSession
    let editing: PaymentTodo?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amountText = ""
    @State private var currency: Currency?
    @State private var reopen = false
    @State private var problem: String?
    @State private var didLoad = false

    var body: some View {
        let currency = self.currency ?? session.ledger.base
        NavigationStack {
            Form {
                Section {
                    TextField("Kameti, rent, car fuel…", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("toPay.name")
                    HStack {
                        CurrencyMenu(ledger: session.ledger, currency: currency, size: 17) { self.currency = $0 }
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad).monospacedDigit()
                            .accessibilityIdentifier("toPay.amount")
                    }
                } footer: {
                    if let editing, editing.paid.minorUnits > 0 {
                        Text("Paid so far: \(MoneyFormatter.string(editing.paid)).")
                    }
                }
                if let editing, editing.isDone {
                    Section {
                        Toggle("Put back on the list", isOn: $reopen)
                    } footer: {
                        Text("Starts again from nothing paid.")
                    }
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(UZColor.negative) }
                }
            }
            .navigationTitle(editing == nil ? "New payment" : "Edit payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold).accessibilityIdentifier("toPay.save")
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                if let editing {
                    name = editing.name
                    amountText = MarkPaidSheet.plain(editing.amount)
                    self.currency = editing.amount.currency
                }
            }
        }
    }

    private func save() {
        let currency = self.currency ?? session.ledger.base
        guard let amount = try? AmountParser.parse(amountText, currency: currency), amount.minorUnits > 0 else {
            problem = "Enter the amount."
            return
        }
        var todo = editing ?? PaymentTodo(name: name, amount: amount)
        todo.name = name.trimmingCharacters(in: .whitespaces)
        todo.amount = amount
        if reopen || todo.paid.currency != currency {
            todo.paid = .zero(currency)
            todo.doneAt = nil
        } else if todo.paid.minorUnits >= amount.minorUnits {
            todo.doneAt = todo.doneAt ?? Date()
        } else {
            todo.doneAt = nil
        }
        guard !todo.name.isEmpty else { problem = "Give it a name."; return }
        if session.perform("Couldn't save. Try again.", { try session.calendar.savePaymentTodo(todo) }) {
            dismiss()
        }
    }
}

/// Paying a to-do: all of it, or a part. Optionally saved as spending from an account in the same currency,
/// so "You have" goes down too.
struct PayTodoSheet: View {
    @Bindable var session: AppSession
    let todo: PaymentTodo
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var accountID: UUID?
    @State private var problem: String?
    @State private var didLoad = false

    private var accounts: [Account] { session.ledger.activeAccounts.filter { $0.currency == todo.amount.currency } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Left to pay", value: MoneyFormatter.string(todo.remaining))
                    HStack {
                        Text(todo.amount.currency.symbol).foregroundStyle(UZColor.label2)
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad).monospacedDigit()
                            .accessibilityIdentifier("toPay.payAmount")
                    }
                } header: {
                    Text(todo.name)
                } footer: {
                    Text("Change the amount if you paid only a part. The rest stays on the list.")
                }
                Section {
                    Picker("Paid from", selection: $accountID) {
                        Text("Don't add as spending").tag(UUID?.none)
                        ForEach(accounts) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    .accessibilityIdentifier("toPay.account")
                } footer: {
                    Text("Pick the account to also save it as spending, so its balance goes down.")
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(UZColor.negative) }
                }
            }
            .navigationTitle("Pay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Paid", action: pay).fontWeight(.semibold).accessibilityIdentifier("toPay.paid")
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                amountText = MarkPaidSheet.plain(todo.remaining)
            }
        }
    }

    private func pay() {
        guard let part = try? AmountParser.parse(amountText, currency: todo.amount.currency), part.minorUnits > 0 else {
            problem = "Enter what you paid."
            return
        }
        let next: PaymentTodo
        do {
            next = try todo.paying(part)
        } catch {
            if case .moreThanLeft(let left) = error {
                problem = "That's more than the \(MoneyFormatter.string(left)) left."
            } else {
                problem = "Enter what you paid."
            }
            return
        }
        if let accountID {
            // Spending needs a category: what UZee would guess for the name, else "Other".
            let pickable = session.ledger.categories.filter { $0.type == .expense && !$0.isHidden }
            let remembered = (try? session.activity.rememberedCategories()) ?? [:]
            let category = CategorySuggester.suggest(payee: todo.name, remembered: remembered, categories: pickable)
                ?? pickable.first { $0.name.lowercased().hasPrefix("other") }?.id ?? pickable.first?.id
            let draft = TransactionDraft(kind: .expense, status: .posted, amount: part, accountID: accountID, categoryID: category,
                                         payeeName: todo.name,
                                         occurredAt: Date(), timeZone: .current, source: .manual)
            guard let built = try? TransactionValidator.build(draft, accounts: session.ledger.accounts, base: session.ledger.base),
                  session.save(built, isNew: true) else {
                problem = "Couldn't save the spending. Try again, or pick \"Don't add as spending\"."
                return
            }
        }
        if session.perform("Couldn't save. Try again.", { try session.calendar.savePaymentTodo(next) }) {
            session.toasts.show(next.isDone ? "\(todo.name) paid" : "\(MoneyFormatter.string(next.remaining)) left for \(todo.name)")
            dismiss()
        }
    }
}

/// Which accounts count in "You have".
struct HaveAccountsSheet: View {
    @Bindable var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var excluded: Set<String> = Set(UserDefaults.standard.stringArray(forKey: ToPayView.excludedKey) ?? [])

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(session.ledger.activeAccounts.filter(\.includeInTotals)) { account in
                        Toggle(isOn: Binding(get: { !excluded.contains(account.id.uuidString) },
                                             set: { on in if on { excluded.remove(account.id.uuidString) } else { excluded.insert(account.id.uuidString) } })) {
                            LabeledContent(account.name, value: MoneyFormatter.string(session.ledger.balance(of: account)))
                        }
                    }
                } footer: {
                    Text("Only the accounts you switch on count in \"You have\".")
                }
            }
            .navigationTitle("You have")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        UserDefaults.standard.set(excluded.sorted(), forKey: ToPayView.excludedKey)
                        session.reload()
                        dismiss()
                    }
                }
            }
        }
    }
}
