import SwiftUI
import UZeeCore

/// Add or edit a transaction (SCR-05, TXN-01…07). Amount first; account defaults to the last used one;
/// recent categories come first; Save shows a confirm sheet, then "Saved · Undo" (AUD-13).
struct AddSheet: View {
    @Bindable var session: AppSession
    @Environment(\.dismiss) private var dismiss

    /// Types offered in the sheet; loans, kameti and installments get their own flows in M5–M6.
    static let kinds: [TransactionKind] = [.expense, .income, .transfer, .refund]

    @State private var kind: TransactionKind = .expense
    @State private var amountText = ""
    @State private var receivedText = ""
    @State private var accountID: UUID?
    @State private var toAccountID: UUID?
    @State private var categoryID: UUID?
    @State private var payee = ""
    /// The category filled in from the payee; replaced while the user hasn't picked another (CAT-007/008).
    @State private var suggestedCategoryID: UUID?
    @State private var remembered: [String: UUID]?
    @State private var note = ""
    @State private var date = Date()
    @State private var isPending = false
    @State private var problem: String?
    @State private var review: MoneyTransaction?
    @State private var editing: MoneyTransaction?
    @State private var didLoad = false
    @FocusState private var amountFocused: Bool

    private var ledger: LedgerSnapshot { session.ledger }
    private var account: Account? { ledger.account(accountID) }
    private var toAccount: Account? { ledger.account(toAccountID) }
    private var currency: Currency { account?.currency ?? ledger.base }
    private var needsReceived: Bool {
        kind == .transfer && account != nil && toAccount != nil && account?.currency != toAccount?.currency
    }

    var body: some View {
        NavigationStack {
            Form {
                amountSection
                if kind == .transfer { transferSection } else { detailsSection }
                Section {
                    DatePicker("Date", selection: $date)
                        .accessibilityIdentifier("add.date")
                    TextField("Note", text: $note, axis: .vertical)
                        .accessibilityIdentifier("add.note")
                    Toggle("Pending (not in balance yet)", isOn: $isPending)
                        .accessibilityIdentifier("add.pending")
                }
                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(UZColor.negative)
                            .accessibilityIdentifier("add.problem")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("add.close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: prepare)
                        .accessibilityIdentifier("add.save")
                }
            }
            .sheet(item: $review) { transaction in
                ConfirmSheet(title: confirmTitle, amount: transaction.amount, rows: confirmRows(transaction),
                             confirmTitle: editing == nil ? "Save" : "Save changes") {
                    if session.save(transaction, isNew: editing == nil) {
                        session.isAddPresented = false
                    }
                }
            }
            .onAppear(perform: load)
            .onChange(of: accountID) { problem = nil }
            .onChange(of: kind) { _, newKind in
                problem = nil
                if let category = ledger.category(categoryID), category.type != categoryType(for: newKind) { categoryID = nil }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
        // .contain keeps child identifiers visible to UI tests.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("add.sheet")
    }

    // MARK: Sections

    private var amountSection: some View {
        Section {
            Picker("Type", selection: $kind) {
                ForEach(Self.kinds, id: \.self) { Text($0.name).tag($0) }
            }
            .disabled(editing != nil)
            .accessibilityIdentifier("add.type")
            HStack(spacing: UZSpacing.s) {
                Text(currency.symbol)
                    .font(.system(.largeTitle, weight: .bold))
                    .foregroundStyle(UZColor.label2)
                TextField("0", text: $amountText)
                    .font(.system(.largeTitle, weight: .bold))
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .monospacedDigit()
                    .accessibilityLabel(kind == .transfer ? "Amount sent" : "Amount")
                    .accessibilityIdentifier("add.amount")
            }
        }
    }

    private var detailsSection: some View {
        Section {
            accountPicker("Account", selection: $accountID, identifier: "add.account")
            let recents = recentCategories
            if !recents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: UZSpacing.m) {
                        ForEach(recents) { category in
                            Button {
                                categoryID = category.id
                            } label: {
                                Label(category.name, systemImage: category.group.symbolName)
                                    .font(.subheadline)
                                    .padding(.horizontal, UZSpacing.l)
                                    .padding(.vertical, UZSpacing.s)
                                    .background(categoryID == category.id ? UZColor.tint.opacity(0.2) : UZColor.fill, in: .capsule)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("add.recent.\(category.name)")
                        }
                    }
                }
            }
            NavigationLink {
                CategoryPicker(categories: ledger.categories, type: categoryType(for: kind), selection: $categoryID)
            } label: {
                LabeledContent("Category") {
                    Text(ledger.categoryPath(categoryID) ?? "Choose").foregroundStyle(categoryID == nil ? UZColor.label2 : UZColor.label)
                }
            }
            .accessibilityIdentifier("add.category")
            TextField(kind == .income ? "From (payer)" : "Paid to (payee)", text: $payee)
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("add.payee")
                .onChange(of: payee) { _, newPayee in suggestCategory(for: newPayee) }
        }
    }

    private func suggestCategory(for payee: String) {
        guard categoryID == nil || categoryID == suggestedCategoryID else { return }
        if remembered == nil { remembered = (try? session.activity.rememberedCategories()) ?? [:] }
        let pickable = ledger.categories.filter { $0.type == categoryType(for: kind) }
        let suggestion = CategorySuggester.suggest(payee: payee, remembered: remembered ?? [:], categories: pickable)
        categoryID = suggestion
        suggestedCategoryID = suggestion
    }

    private var transferSection: some View {
        Section {
            accountPicker("From", selection: $accountID, identifier: "add.from")
            accountPicker("To", selection: $toAccountID, identifier: "add.to")
            if needsReceived, let toAccount {
                HStack {
                    Text("Arrived").foregroundStyle(UZColor.label2)
                    Spacer()
                    Text(toAccount.currency.symbol).foregroundStyle(UZColor.label2)
                    TextField("0", text: $receivedText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 160)
                        .accessibilityLabel("Amount that arrived")
                        .accessibilityIdentifier("add.received")
                }
                if let rateLine { Text(rateLine).font(.footnote).foregroundStyle(UZColor.label2).accessibilityIdentifier("add.rate") }
            }
        } footer: {
            Text("Transfers move your own money. They are not spending or income.")
        }
    }

    private func accountPicker(_ label: String, selection: Binding<UUID?>, identifier: String) -> some View {
        Picker(label, selection: selection) {
            Text("Choose").tag(UUID?.none)
            ForEach(ledger.activeAccounts) { account in
                Text(account.currency == ledger.base ? account.name : "\(account.name) (\(account.currency.code))")
                    .tag(UUID?.some(account.id))
            }
        }
        .accessibilityIdentifier(identifier)
    }

    // MARK: Logic

    private var title: String {
        if editing != nil { return "Edit \(kind.name.lowercased())" }
        return "New \(kind.name.lowercased())"
    }

    private var confirmTitle: String { editing == nil ? "Save this \(kind.name.lowercased())?" : "Save changes?" }

    private func categoryType(for kind: TransactionKind) -> CategoryType {
        kind == .income ? .income : .expense
    }

    /// Up to four categories used most recently for this type (TXN-010).
    private var recentCategories: [SpendCategory] {
        var seen = Set<UUID>()
        var result: [SpendCategory] = []
        for transaction in session.transactions where transaction.kind == kind {
            guard let id = transaction.categoryID, !seen.contains(id), let category = ledger.category(id),
                  category.type == categoryType(for: kind) else { continue }
            seen.insert(id)
            result.append(category)
            if result.count == 4 { break }
        }
        return result
    }

    /// "Rate 278.70 · Rs 650 less than at 280" for a cross-currency transfer (TXN-03).
    private var rateLine: String? {
        guard let account, let toAccount,
              let sent = try? AmountParser.parse(amountText, currency: account.currency),
              let received = try? AmountParser.parse(receivedText, currency: toAccount.currency),
              sent.minorUnits > 0, received.minorUnits > 0 else { return nil }
        let (foreign, base) = account.currency == ledger.base ? (received, sent) : (sent, received)
        let tableRate = ledger.rate(for: foreign.currency)
        guard let rate = try? TransferRate(foreign: foreign, base: base, tableRate: tableRate) else { return nil }
        let table = ExchangeRate.display(tableRate)
        let difference = rate.differenceFromTable
        let comparison: String
        if difference.isZero {
            comparison = "same as \(table)"
        } else {
            let magnitude = Money(minorUnits: difference.minorUnits.magnitudeClamped, currency: difference.currency)
            comparison = "\(MoneyFormatter.string(magnitude)) \(difference.isNegative ? "less" : "more") than at \(table)"
        }
        return "Rate \(ExchangeRate.display(rate.rate)) · \(comparison)"
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        switch session.addRequest {
        case .new:
            accountID = defaultAccountID()
            amountFocused = true
        case .transfer:
            kind = .transfer
            accountID = defaultAccountID()
            amountFocused = true
        case .edit(let transaction):
            editing = transaction
            fill(from: transaction, keepDate: true)
        case .repeatOf(let transaction):
            fill(from: transaction, keepDate: false)
        }
    }

    private func defaultAccountID() -> UUID? {
        let active = ledger.activeAccounts
        if let last = try? session.client.lastUsedAccountID(), active.contains(where: { $0.id == last }) { return last }
        return active.first?.id
    }

    private func fill(from transaction: MoneyTransaction, keepDate: Bool) {
        let draft = TransactionValidator.draft(from: transaction)
        kind = Self.kinds.contains(draft.kind) ? draft.kind : .expense
        amountText = draft.amount.map(plainNumber) ?? ""
        accountID = draft.accountID
        toAccountID = draft.toAccountID
        if let received = draft.receivedAmount, received.currency != draft.amount?.currency { receivedText = plainNumber(received) }
        categoryID = draft.categoryID
        payee = draft.payeeName ?? ""
        note = draft.note ?? ""
        isPending = draft.status == .pending
        date = keepDate ? draft.occurredAt : Date()
    }

    /// Validates and opens the confirm sheet; nothing is written until Confirm (SMK-012: input stays for fixing).
    private func prepare() {
        problem = nil
        let amount: Money
        do {
            amount = try AmountParser.parse(amountText, currency: currency)
        } catch {
            problem = ProblemText.message(error)
            return
        }
        var received: Money?
        if needsReceived, let toAccount {
            do {
                received = try AmountParser.parse(receivedText, currency: toAccount.currency)
            } catch {
                problem = error == .empty ? ProblemText.message(TransactionProblem.missingReceivedAmount) : ProblemText.message(error)
                return
            }
        }
        let draft = TransactionDraft(
            kind: kind, status: isPending ? .pending : .posted, amount: amount, accountID: accountID,
            toAccountID: kind == .transfer ? toAccountID : nil, receivedAmount: received,
            categoryID: kind == .transfer ? nil : categoryID, payeeName: kind == .transfer ? nil : payee, note: note,
            occurredAt: date, timeZone: editing.flatMap { TimeZone(identifier: $0.timeZoneID) } ?? .current,
            source: editing?.source ?? .manual)
        do {
            review = try TransactionValidator.build(draft, accounts: ledger.accounts, base: ledger.base, existing: editing)
        } catch {
            problem = ProblemText.message(error)
        }
    }

    private func confirmRows(_ transaction: MoneyTransaction) -> [ConfirmSheet.Row] {
        var rows: [ConfirmSheet.Row] = []
        if transaction.kind == .transfer {
            if let out = transaction.legs.first(where: { $0.role == .transferOut }), let from = ledger.account(out.accountID) {
                rows.append(.init("From", from.name))
            }
            if let into = transaction.legs.first(where: { $0.role == .transferIn }), let to = ledger.account(into.accountID) {
                rows.append(.init("To", "\(to.name) · \(MoneyFormatter.string(into.amount))"))
            }
            if let rate = transaction.fxRate { rows.append(.init("Rate", ExchangeRate.display(rate))) }
        } else {
            if let leg = transaction.legs.first, let account = ledger.account(leg.accountID) { rows.append(.init("Account", account.name)) }
            if let path = ledger.categoryPath(transaction.categoryID) { rows.append(.init("Category", path)) }
            if let payee = transaction.payeeName { rows.append(.init(transaction.kind == .income ? "From" : "Paid to", payee)) }
        }
        rows.append(.init("Date", transaction.occurredAt.formatted(date: .abbreviated, time: .shortened)))
        if transaction.status == .pending { rows.append(.init("Status", "Pending")) }
        return rows
    }
}

/// Category list for one tree, parents with their subcategories (CAT-01). Hidden categories are left out.
struct CategoryPicker: View {
    let categories: [SpendCategory]
    let type: CategoryType
    @Binding var selection: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(parents) { parent in
                Section {
                    row(parent, isParent: true)
                    ForEach(children(of: parent)) { child in row(child, isParent: false) }
                }
            }
        }
        .navigationTitle("Category")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var parents: [SpendCategory] {
        categories.filter { $0.type == type && $0.parentID == nil && !$0.isHidden }
    }

    private func children(of parent: SpendCategory) -> [SpendCategory] {
        categories.filter { $0.parentID == parent.id && !$0.isHidden }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func row(_ category: SpendCategory, isParent: Bool) -> some View {
        Button {
            selection = category.id
            dismiss()
        } label: {
            HStack(spacing: UZSpacing.l) {
                if isParent { CategoryTile(category.group, size: 30) } else { Color.clear.frame(width: 30, height: 1) }
                Text(category.name).font(isParent ? .body.weight(.semibold) : .body)
                Spacer()
                if selection == category.id { Image(systemName: "checkmark").foregroundStyle(UZColor.tint) }
            }
        }
        .foregroundStyle(UZColor.label)
        .accessibilityIdentifier("category.\(category.name)")
        .accessibilityAddTraits(selection == category.id ? .isSelected : [])
    }
}
