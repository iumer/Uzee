import SwiftUI
import UZeeCore

/// Accounts list (SCR-11): every account with its derived balance, the available total, archived ones last.
struct AccountsView: View {
    @Bindable var session: AppSession
    @State private var isAdding = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: UZSpacing.xs) {
                    Text("Available").font(.subheadline).foregroundStyle(UZColor.label2)
                    AmountText(session.ledger.available, font: .title.bold())
                    if let footnote = session.ledger.footnote {
                        Text(footnote).font(.caption).foregroundStyle(UZColor.label2)
                    }
                }
                .padding(.vertical, UZSpacing.xs)
                .accessibilityIdentifier("accounts.total")
            }
            let active = session.ledger.activeAccounts
            if !active.isEmpty {
                Section("Accounts") {
                    ForEach(active) { account in
                        NavigationLink(value: Route.account(account.id)) {
                            AccountRow(account: account, ledger: session.ledger)
                        }
                        .accessibilityIdentifier("account.\(account.name)")
                    }
                }
            }
            let archived = session.ledger.accounts.filter(\.isArchived)
            if !archived.isEmpty {
                Section("Archived") {
                    ForEach(archived) { account in
                        NavigationLink(value: Route.account(account.id)) {
                            AccountRow(account: account, ledger: session.ledger)
                        }
                        .accessibilityIdentifier("account.\(account.name)")
                    }
                }
            }
        }
        .overlay {
            if session.ledger.accounts.isEmpty {
                EmptyStateView("No accounts yet", systemImage: "building.columns",
                               description: "Add the accounts you use. Balances come from your transactions.")
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add account")
                    .accessibilityIdentifier("accounts.add")
            }
        }
        .sheet(isPresented: $isAdding) { AccountFormSheet(session: session, editing: nil) }
    }
}

/// One account: balance, its transactions, edit, reconcile, archive or delete (ACC-04, ACC-05).
struct AccountDetailView: View {
    @Bindable var session: AppSession
    let accountID: UUID
    @State private var isEditing = false
    @State private var isReconciling = false
    @State private var confirmArchive = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let account = session.ledger.account(accountID) {
            content(account)
        } else {
            EmptyStateView("Account removed", systemImage: "building.columns", description: "This account no longer exists.")
        }
    }

    private func content(_ account: Account) -> some View {
        let rows = session.transactions.filter { $0.legs.contains { $0.accountID == accountID } }
        return List {
            Section {
                VStack(alignment: .leading, spacing: UZSpacing.xs) {
                    Text("Balance").font(.subheadline).foregroundStyle(UZColor.label2)
                    AmountText(session.ledger.balance(of: account), style: .transfer, font: .title.bold(),
                               base: session.ledger.base, rate: session.ledger.rate(for: account.currency))
                    Text("Opening \(MoneyFormatter.string(account.openingBalance)) on \(account.openingDate.listTitle(today: today))")
                        .font(.caption).foregroundStyle(UZColor.label2)
                }
                .padding(.vertical, UZSpacing.xs)
                // One element for VoiceOver and UI tests: "Balance", value "8,500 rupees".
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Balance")
                .accessibilityValue(MoneyFormatter.spoken(session.ledger.balance(of: account)))
                .accessibilityIdentifier("account.balance")
                if !account.isArchived {
                    Button("Reconcile balance") { isReconciling = true }
                        .accessibilityIdentifier("account.reconcile")
                    Button("Import statement") { session.openImport(account: accountID) }
                        .accessibilityIdentifier("account.import")
                }
            }
            Section("Transactions") {
                if rows.isEmpty {
                    Text("No transactions yet").foregroundStyle(UZColor.label2)
                }
                ForEach(rows) { transaction in
                    NavigationLink(value: Route.transaction(transaction.id)) {
                        TransactionRow(transaction: transaction, ledger: session.ledger, accountID: accountID)
                    }
                }
            }
            Section {
                if rows.isEmpty {
                    Button("Delete account", role: .destructive) { confirmDelete = true }
                        .accessibilityIdentifier("account.delete")
                } else {
                    Button(account.isArchived ? "Unarchive" : "Archive account") {
                        if account.isArchived {
                            session.perform("Couldn't unarchive. Try again.") { try session.client.setArchived(false, accountID) }
                        } else {
                            confirmArchive = true
                        }
                    }
                    .accessibilityIdentifier("account.archive")
                    Text("Accounts with transactions can be archived, not deleted, so your history stays complete.")
                        .font(.footnote).foregroundStyle(UZColor.label2)
                }
            }
        }
        .navigationTitle(account.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }.accessibilityIdentifier("account.edit")
            }
        }
        .sheet(isPresented: $isEditing) { AccountFormSheet(session: session, editing: account) }
        .sheet(isPresented: $isReconciling) { ReconcileSheet(session: session, account: account) }
        .confirmationDialog("Archive \(account.name)?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Archive") {
                session.perform("Couldn't archive. Try again.") { try session.client.setArchived(true, accountID) }
            }
        } message: {
            Text("It leaves pickers. Its history stays, and it can be unarchived.")
        }
        .confirmationDialog("Delete \(account.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if session.perform("Couldn't delete the account. Try again.", { try session.client.deleteAccount(accountID) }) {
                    dismiss()
                }
            }
        }
    }

    private var today: LocalDate { LocalDate(Date(), in: .current) }
}

/// Add or edit an account (ACC-001, ACC-008). Currency locks once the account has transactions.
struct AccountFormSheet: View {
    @Bindable var session: AppSession
    let editing: Account?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: AccountKind = .bank
    @State private var currency: Currency = .pkr
    @State private var opening = ""
    @State private var openingDate = Date()
    @State private var includeInTotals = true
    @State private var currencyLocked = false
    @State private var problem: String?

    /// Banks and wallets people in Pakistan use most; one tap fills the name and type.
    static let presets: [(name: String, kind: AccountKind)] = [
        ("Cash", .cash), ("HBL", .bank), ("Meezan", .bank), ("MCB", .bank), ("UBL", .bank), ("Allied", .bank),
        ("Bank Alfalah", .bank), ("SadaPay", .wallet), ("NayaPay", .wallet), ("Easypaisa", .wallet),
        ("JazzCash", .wallet), ("Wise", .multiCurrency)
    ]

    var body: some View {
        NavigationStack {
            Form {
                if editing == nil {
                    Section("Quick pick") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: UZSpacing.s) {
                                ForEach(Self.presets, id: \.name) { preset in
                                    Button(preset.name) {
                                        name = preset.name
                                        kind = preset.kind
                                        if preset.kind == .multiCurrency { currency = .usd }
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(name == preset.name ? UZColor.tint : .secondary)
                                    .accessibilityIdentifier("accountForm.preset.\(preset.name)")
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                Section {
                    TextField("Name, e.g. HBL", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("accountForm.name")
                    Picker("Type", selection: $kind) {
                        ForEach(AccountKind.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    Picker("Currency", selection: $currency) {
                        Text("PKR (Rs)").tag(Currency.pkr)
                        Text("USD ($)").tag(Currency.usd)
                    }
                    .disabled(currencyLocked)
                    .accessibilityIdentifier("accountForm.currency")
                } footer: {
                    if currencyLocked { Text("Currency can't change once the account has transactions.") }
                }
                Section {
                    TextField("Opening balance", text: $opening)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("accountForm.opening")
                    DatePicker("On", selection: $openingDate, displayedComponents: .date)
                    Toggle("Include in Available", isOn: $includeInTotals)
                } footer: {
                    Text("The balance on that day. After that, the balance comes from your transactions.")
                }
                if let problem {
                    Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(UZColor.negative) }
                        .accessibilityIdentifier("accountForm.problem")
                }
            }
            .navigationTitle(editing == nil ? "New account" : "Edit account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("accountForm.save")
                }
            }
            .onAppear(perform: load)
        }
        .presentationSizing(.form)
    }

    private func load() {
        guard let editing else { return }
        name = editing.name
        kind = editing.kind
        currency = editing.currency
        opening = editing.openingBalance.isZero ? "" : plainNumber(editing.openingBalance)
        openingDate = editing.openingDate.startDate(in: .current)
        includeInTotals = editing.includeInTotals
        currencyLocked = (try? session.client.hasTransactions(editing.id)) ?? true
    }

    private func save() {
        let openingMoney: Money
        do {
            openingMoney = opening.trimmingCharacters(in: .whitespaces).isEmpty ? .zero(currency) : try parseSigned(opening)
        } catch {
            problem = ProblemText.message(error)
            return
        }
        let day = LocalDate(openingDate, in: .current)
        do {
            if var account = editing {
                account.name = name
                account.kind = kind
                account.currency = currency
                account.openingBalance = openingMoney
                account.openingDate = day
                account.includeInTotals = includeInTotals
                try session.client.updateAccount(account)
            } else {
                _ = try session.client.createAccount(.init(name: name, kind: kind, currency: currency, openingBalance: openingMoney,
                                                           openingDate: day, includeInTotals: includeInTotals))
            }
            session.reload()
            session.toasts.show(editing == nil ? "Account added" : "Account saved")
            dismiss()
        } catch let error as Account.Problem {
            problem = switch error {
            case .emptyName: "Enter a name."
            case .nameTooLong: "Use a shorter name (40 characters at most)."
            case .duplicateName: "You already have an account with this name."
            case .currencyLocked: "Currency can't change once the account has transactions."
            }
        } catch {
            problem = "Couldn't save. Try again."
        }
    }

    /// Opening balances may be negative (credit card): "-500" is allowed here only.
    private func parseSigned(_ text: String) throws(AmountParser.Failure) -> Money {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let negative = trimmed.hasPrefix("-") || trimmed.hasPrefix("\u{2212}")
        let value = try AmountParser.parse(negative ? String(trimmed.dropFirst()) : trimmed, currency: currency)
        return negative ? Money(minorUnits: -value.minorUnits, currency: currency) : value
    }
}

/// "123456.78" for editing a stored amount (no grouping, all minor digits).
func plainNumber(_ money: Money) -> String {
    let digits = money.currency.minorUnits
    let scale = Int64(pow(10, Double(digits)))
    let magnitude = money.minorUnits.magnitudeClamped
    let whole = magnitude / scale
    let fraction = magnitude % scale
    var text = (money.minorUnits < 0 ? "-" : "") + String(whole)
    if fraction != 0 {
        let padded = String(fraction)
        text += "." + String(repeating: "0", count: digits - padded.count) + padded
    }
    return text
}

/// Reconcile (ACC-04): enter the real balance; the difference is posted as a visible adjustment.
struct ReconcileSheet: View {
    @Bindable var session: AppSession
    let account: Account
    @Environment(\.dismiss) private var dismiss
    @State private var real = ""
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("UZee shows") { Text(MoneyFormatter.string(session.ledger.balance(of: account))) }
                    TextField("Real balance now", text: $real)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("reconcile.amount")
                } footer: {
                    Text("The difference is saved as a balance adjustment. It isn't counted as spending or income.")
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(UZColor.negative) }
                }
            }
            .navigationTitle("Reconcile \(account.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.accessibilityIdentifier("reconcile.save") }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let target: Money
        do { target = try AmountParser.parse(real, currency: account.currency) } catch {
            problem = ProblemText.message(error)
            return
        }
        let current = session.ledger.balance(of: account)
        let difference = target.minorUnits - current.minorUnits
        guard difference != 0 else { dismiss(); return }
        let draft = TransactionDraft(kind: .adjustment, amount: Money(minorUnits: difference.magnitudeClamped, currency: account.currency),
                                     accountID: account.id, adjustmentIncreases: difference > 0, note: "Reconciled to \(MoneyFormatter.string(target))")
        do {
            let transaction = try TransactionValidator.build(draft, accounts: session.ledger.accounts, base: session.ledger.base)
            if session.save(transaction, isNew: true) { dismiss() }
        } catch {
            problem = ProblemText.message(error)
        }
    }
}
