import SwiftUI
import UniformTypeIdentifiers
import UZeeCore

/// One statement row on the review screen (IMP-02).
struct ImportRow: Identifiable, Equatable {
    let id: Int
    var date: LocalDate
    let description: String
    var payee: String
    /// Positive amount; `isMoneyIn` says the direction.
    var amount: Money
    var isMoneyIn: Bool
    var categoryID: UUID?
    var include: Bool
    /// Already in UZee (IMP-03).
    let duplicateOf: UUID?
}

/// Statement import (SCR-34, J11): pick a PDF or CSV; UZee recognises the bank and the currency and suggests the
/// matching account (or adds one), then review and import in one step with Undo.
struct ImportStatementView: View {
    @Bindable var session: AppSession
    @Environment(\.dismiss) private var dismiss

    enum Step: Equatable {
        case choose
        case reading
        case review
        case done(Int)
    }

    @State private var step: Step = .choose
    @State private var accountID: UUID?
    @State private var showingFiles = false
    @State private var fileURL: URL?
    @State private var fileName = ""
    @State private var problem: String?
    @State private var askingPassword = false
    @State private var password = ""
    @State private var rows: [ImportRow] = []
    @State private var guessedSigns = false
    @State private var reading: StatementReading?
    /// The bank the statement is from: recognised, or chosen by the user when UZee doesn't know the layout.
    @State private var bankName = ""
    /// The statement's currency: from its header, or chosen by the user.
    @State private var statementCurrency: Currency = .pkr
    @State private var currencyRecognised = false
    @State private var accountProblem: String?
    @State private var confirming = false

    private var ledger: LedgerSnapshot { session.ledger }
    private var account: Account? { ledger.account(accountID) }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .choose: chooseStep
                case .reading: readingStep
                case .review: reviewStep
                case .done(let count): doneStep(count)
                }
            }
            .background(UZColor.bg)
            .navigationTitle("Import statement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .review ? "Cancel" : "Close") { dismiss() }
                        .accessibilityIdentifier("import.close")
                }
            }
            .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.pdf, .commaSeparatedText, .plainText]) { result in
                guard case .success(let url) = result else { return }
                fileURL = url
                fileName = url.lastPathComponent
                password = ""
                read()
            }
            .alert("This PDF has a password", isPresented: $askingPassword) {
                SecureField("Password", text: $password)
                Button("Open") { read() }
                Button("Cancel", role: .cancel) { step = .choose }
            } message: {
                Text("Banks often use your CNIC, date of birth or account number. UZee doesn't keep the password.")
            }
            .onChange(of: accountID) { rebuildRows() }
        }
        .presentationDetents([.large])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("import.sheet")
    }

    // MARK: Step 1: the file

    private var chooseStep: some View {
        Form {
            Section {
                Button {
                    problem = nil
                    showingFiles = true
                } label: {
                    Label("Choose a PDF or CSV statement", systemImage: "doc.text")
                }
                .accessibilityIdentifier("import.pick")
                if let problem {
                    Text(problem).foregroundStyle(UZColor.negative)
                        .accessibilityIdentifier("import.problem")
                }
            } header: {
                Text("Step 1 of 2 · Pick the statement")
            } footer: {
                Text("Download the statement from your bank's app or website first. UZee works out the bank and the currency, then asks which account it belongs to. It reads the file on this iPhone; nothing is uploaded.")
            }
            Section("Reads") {
                Text("MCB, HBL, Meezan Bank, SadaPay, NayaPay and Wise statements, and most other banks' PDF or CSV statements with a date, an amount and a balance on each row.")
                    .font(.footnote).foregroundStyle(UZColor.label2)
            }
        }
    }

    private var readingStep: some View {
        VStack(spacing: UZSpacing.l) {
            ProgressView()
            Text("Reading \(fileName)…").font(.headline)
            Text("Finding dates, amounts and payees. Nothing leaves this iPhone.")
                .font(.subheadline).foregroundStyle(UZColor.label2).multilineTextAlignment(.center)
        }
        .padding(UZSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("import.reading")
    }

    private func read() {
        guard let fileURL else { return }
        step = .reading
        problem = nil
        let smart = session.smart
        let secret = password.isEmpty ? nil : password
        Task {
            let result = await Task.detached { () -> Result<SmartClient.StatementText, Error> in
                Result { try smart.readStatement(fileURL, secret) }
            }.value
            switch result {
            case .success(.pdf(let versions)):
                review(StatementParser.read(versions: versions))
            case .success(.csv(let text)):
                guard let reading = StatementParser.read(csv: text) else {
                    fail("UZee couldn't find dates and amounts in this CSV. Check it has Date and Amount (or Debit and Credit) columns.")
                    return
                }
                review(reading)
            case .failure(let error):
                switch error as? StatementFileProblem {
                case .needsPassword:
                    step = .choose
                    askingPassword = true
                case .wrongPassword:
                    password = ""
                    step = .choose
                    problem = "That password didn't open the PDF. Try again."
                    askingPassword = true
                case .noText:
                    fail("This PDF is a scan (pictures of pages), so UZee can't read the text. Download the statement again as a regular PDF or CSV.")
                default:
                    fail("Couldn't read this file. Try another PDF or CSV.")
                }
            }
        }
    }

    private func fail(_ message: String) {
        problem = message
        step = .choose
    }

    private func review(_ reading: StatementReading) {
        guard !reading.rows.isEmpty else {
            if let source = reading.source {
                fail("This \(source.rawValue) statement has no transactions in it.")
            } else {
                fail("UZee can't read this bank's statement format yet. Share a sample statement so a reader can be added for this bank.")
            }
            return
        }
        self.reading = reading
        bankName = reading.source?.rawValue ?? ""
        let recognised = reading.currencyCode.flatMap(Currency.known(code:))
        currencyRecognised = recognised != nil
        statementCurrency = recognised ?? ledger.base
        rows = []
        accountID = bestAccount()
        accountProblem = nil
        rebuildRows()
        step = .review
    }

    /// The account this statement most likely belongs to: same currency, then the bank's name in the account's
    /// name, then the account Import was opened from. Nil when no account has the statement's currency.
    private func bestAccount() -> UUID? {
        let bank = NameKey.make(bankShortName)
        let matching = ledger.activeAccounts.filter { $0.currency == statementCurrency }
        func score(_ account: Account) -> Int {
            var points = 0
            if !bank.isEmpty, NameKey.make(account.name).contains(bank) { points += 4 }
            if account.id == session.importAccountID { points += 2 }
            if bankName == StatementSource.wise.rawValue, account.kind == .multiCurrency { points += 1 }
            return points
        }
        return matching.max { score($0) < score($1) }?.id
    }

    /// "Meezan Bank" → "Meezan", for matching account names.
    private var bankShortName: String {
        bankName == StatementSource.meezan.rawValue ? "Meezan" : bankName
    }

    /// The name for a new account: "Wise USD", "Meezan Bank", or "Imported USD".
    private var newAccountName: String {
        let bank = bankName.isEmpty ? "Imported" : bankName
        return statementCurrency == ledger.base && !bankName.isEmpty ? bank : "\(bank) \(statementCurrency.code)"
    }

    private func addAccount() {
        let kind: AccountKind = switch bankName {
        case StatementSource.wise.rawValue: .multiCurrency
        case StatementSource.sadapay.rawValue, StatementSource.nayapay.rawValue: .wallet
        default: .bank
        }
        let firstDay = rows.map(\.date).min() ?? session.today
        // The statement's opening balance, as of the day before its first row, so its rows add up to its closing balance.
        let opening = reading?.openingBalance.flatMap { try? Money.fromMajor($0, statementCurrency) } ?? Money(minorUnits: 0, currency: statementCurrency)
        var name = newAccountName
        var suffix = 2
        while ledger.accounts.contains(where: { NameKey.make($0.name) == NameKey.make(name) }) {
            name = "\(newAccountName) \(suffix)"
            suffix += 1
        }
        do {
            let account = try session.client.createAccount(.init(name: name, kind: kind, currency: statementCurrency, openingBalance: opening,
                                                                 openingDate: firstDay.addingDays(-1), includeInTotals: true))
            session.reload()
            accountID = account.id
            accountProblem = nil
            session.toasts.show("Added \(name)")
        } catch {
            accountProblem = "Couldn't add the account. Add it in Accounts, then choose it here."
        }
    }

    /// Rows in the chosen account's currency, with duplicates spotted against that account. Edits are kept.
    private func rebuildRows() {
        guard let reading else { return }
        let currency = account?.currency ?? statementCurrency
        let previous = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let remembered = (try? session.activity.rememberedCategories()) ?? [:]
        var built: [ImportRow] = []
        var candidates: [DuplicateFinder.Candidate] = []
        for row in reading.rows {
            guard let magnitude = try? Money.fromMajor(abs(row.amount), currency), magnitude.minorUnits > 0 else { continue }
            let signed = row.amount < 0 ? ((try? magnitude.negated()) ?? magnitude) : magnitude
            candidates.append(DuplicateFinder.Candidate(date: row.date, amount: signed))
            let id = built.count
            if var kept = previous[id] {
                kept.amount = magnitude
                built.append(kept)
                continue
            }
            let payee = StatementParser.payee(from: row.description)
            let type: CategoryType = row.amount > 0 ? .income : .expense
            let pickable = ledger.categories.filter { $0.type == type && !$0.isHidden }
            let category = CategorySuggester.suggest(payee: payee, remembered: remembered, categories: pickable)
                ?? CategorySuggester.suggest(payee: row.description, remembered: remembered, categories: pickable)
            built.append(ImportRow(id: id, date: row.date, description: row.description, payee: payee, amount: magnitude,
                                   isMoneyIn: row.amount > 0, categoryID: category, include: true, duplicateOf: nil))
        }
        let duplicates = accountID.map { DuplicateFinder.matches(candidates, accountID: $0, in: session.transactions) } ?? [:]
        rows = built.enumerated().map { index, row in
            let match = duplicates[index]
            let include = previous[row.id] != nil && (previous[row.id]?.duplicateOf == nil) == (match == nil) ? row.include : match == nil
            return ImportRow(id: row.id, date: row.date, description: row.description, payee: row.payee, amount: row.amount,
                             isMoneyIn: row.isMoneyIn, categoryID: row.categoryID, include: include, duplicateOf: match)
        }
        guessedSigns = reading.signSource == .words
    }

    /// Why the import can't go ahead yet: no account, or one in another currency (amounts are never imported in the wrong currency).
    private var blocker: String? {
        guard let account else { return "Choose the account this statement belongs to, or add one." }
        guard account.currency == statementCurrency else {
            return "This statement is in \(statementCurrency.code), but \(account.name) is in \(account.currency.code). Choose a \(statementCurrency.code) account or add one."
        }
        return nil
    }

    // MARK: Step 2: account and review

    private var included: [ImportRow] { rows.filter(\.include) }

    private var reviewStep: some View {
        List {
            Section {
                if let source = reading?.source {
                    LabeledContent("Bank", value: source.rawValue)
                        .accessibilityIdentifier("import.bank")
                } else {
                    Picker("Bank", selection: $bankName) {
                        Text("Choose").tag("")
                        ForEach(StatementSource.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
                        Text("Other bank").tag("Other")
                    }
                    .accessibilityIdentifier("import.bank")
                }
                if currencyRecognised {
                    LabeledContent("Currency", value: statementCurrency.code)
                        .accessibilityIdentifier("import.currency")
                } else {
                    Picker("Currency", selection: $statementCurrency) {
                        ForEach(Currency.known, id: \.self) { Text($0.code).tag($0) }
                    }
                    .accessibilityIdentifier("import.currency")
                }
                Picker("Import into", selection: $accountID) {
                    Text("Choose").tag(UUID?.none)
                    ForEach(ledger.activeAccounts) { account in
                        Text(account.currency == ledger.base ? account.name : "\(account.name) (\(account.currency.code))")
                            .tag(UUID?.some(account.id))
                    }
                }
                .accessibilityIdentifier("import.account")
                if !ledger.activeAccounts.contains(where: { $0.currency == statementCurrency && NameKey.make($0.name).contains(NameKey.make(bankShortName)) })
                    || account == nil {
                    Button {
                        addAccount()
                    } label: {
                        Label("Add a “\(newAccountName)” account", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("import.addAccount")
                }
                if let message = accountProblem ?? blocker {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(UZColor.warning)
                        .accessibilityIdentifier("import.blocker")
                }
            } header: {
                Text("Step 2 of 2 · Which account is this?")
            } footer: {
                if reading?.source != nil || currencyRecognised {
                    Text("Recognised from the statement. Rows already in the account are spotted and left out.")
                }
            }
            .onChange(of: statementCurrency) {
                if account?.currency != statementCurrency { accountID = bestAccount() }
            }
            .onChange(of: bankName) {
                if account == nil { accountID = bestAccount() }
            }
            Section {
                VStack(alignment: .leading, spacing: UZSpacing.s) {
                    Text("\(rows.count) transactions found").font(.headline)
                    if let first = rows.map(\.date).min(), let last = rows.map(\.date).max() {
                        Text("\(DateText.long(first)) – \(DateText.long(last))")
                            .font(.subheadline).foregroundStyle(UZColor.label2)
                    }
                    if guessedSigns {
                        Label("This statement has no balance column, so money in and out was guessed from the words. Tap an amount to switch it.",
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(UZColor.warning)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("import.summary")
            }
            let fresh = rows.filter { $0.duplicateOf == nil }
            if !fresh.isEmpty {
                Section("New · \(fresh.count)") {
                    ForEach(fresh) { row in rowView(row) }
                }
            }
            let duplicates = rows.filter { $0.duplicateOf != nil }
            if !duplicates.isEmpty {
                Section {
                    ForEach(duplicates) { row in rowView(row) }
                } header: {
                    Text("Possible duplicates · \(duplicates.count)")
                } footer: {
                    Text("These match a transaction already in UZee on the same day or a day apart, so they're off. Turn one on to import it anyway.")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                confirming = true
            } label: {
                Text(included.isEmpty ? "Nothing to import" : "Import \(included.count) transactions").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(included.isEmpty || blocker != nil)
            .padding(UZSpacing.xxl)
            .background(.bar)
            .accessibilityIdentifier("import.import")
        }
        .confirmationDialog("Import \(included.count) transactions into \(account?.name ?? "this account")?", isPresented: $confirming,
                            titleVisibility: .visible) {
            Button("Import \(included.count) transactions") { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(rows.count - included.count) skipped. You can undo the whole import right after.")
        }
    }

    private func binding(_ row: ImportRow) -> Binding<ImportRow> {
        Binding(get: { rows.first { $0.id == row.id } ?? row },
                set: { value in if let index = rows.firstIndex(where: { $0.id == row.id }) { rows[index] = value } })
    }

    private func rowView(_ row: ImportRow) -> some View {
        let current = binding(row)
        return HStack(spacing: UZSpacing.l) {
            Button {
                current.wrappedValue.include.toggle()
            } label: {
                Image(systemName: row.include ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(row.include ? UZColor.tint : UZColor.label3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.include ? "Included" : "Left out")
            .accessibilityIdentifier("import.row.toggle")
            NavigationLink {
                ImportRowEditor(session: session, row: current)
            } label: {
                VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                    HStack {
                        Text(row.payee).lineLimit(1)
                        Spacer()
                        Text((row.isMoneyIn ? "+" : "−") + MoneyFormatter.string(row.amount))
                            .monospacedDigit()
                            .foregroundStyle(row.isMoneyIn ? UZColor.positive : UZColor.label)
                    }
                    Text("\(DateText.short(row.date)) · \(ledger.categoryPath(row.categoryID) ?? "No category")")
                        .font(.caption).foregroundStyle(UZColor.label2).lineLimit(1)
                }
                .opacity(row.include ? 1 : 0.5)
            }
        }
        .accessibilityIdentifier("import.row")
    }

    /// Saves every included row in one go; Undo removes them all (IMP-003: nothing is saved before this).
    private func save() {
        guard let account, blocker == nil else { return }
        var built: [MoneyTransaction] = []
        for row in included {
            let kind: TransactionKind = row.isMoneyIn ? .income : .expense
            let type: CategoryType = row.isMoneyIn ? .income : .expense
            let category = row.categoryID ?? fallbackCategory(type)
            let noon = row.date.startDate(in: .current).addingTimeInterval(12 * 3_600)
            let draft = TransactionDraft(kind: kind, status: .posted, amount: row.amount, accountID: account.id, categoryID: category,
                                         payeeName: row.payee, note: String(row.description.prefix(TransactionValidator.maxNoteLength)),
                                         occurredAt: noon, timeZone: .current, source: .import)
            guard let transaction = try? TransactionValidator.build(draft, accounts: ledger.accounts, base: ledger.base) else { continue }
            built.append(transaction)
        }
        var saved: [UUID] = []
        do {
            for transaction in built {
                try session.client.save(transaction)
                saved.append(transaction.id)
            }
        } catch {
            for id in saved { try? session.client.discard(id) }
            session.reload()
            session.errorMessage = "Couldn't import. Nothing was added. Try again."
            return
        }
        session.reload()
        let ids = saved
        session.toasts.show("Imported \(ids.count) transactions") { [session] in
            for id in ids { try? session.client.discard(id) }
            session.reload()
        }
        step = .done(ids.count)
    }

    private func fallbackCategory(_ type: CategoryType) -> UUID? {
        let pickable = ledger.categories.filter { $0.type == type && !$0.isHidden }
        return pickable.first { $0.group == .other && $0.parentID == nil }?.id
            ?? pickable.first { NameKey.make($0.name).hasPrefix("other") }?.id
            ?? pickable.first?.id
    }

    // MARK: Done

    private func doneStep(_ count: Int) -> some View {
        VStack(spacing: UZSpacing.l) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(UZColor.positive)
            Text("Imported \(count) transactions").font(.title3.weight(.semibold))
            Text("Into \(account?.name ?? "your account"). Undo is in the message at the bottom for a few seconds.")
                .font(.subheadline).foregroundStyle(UZColor.label2).multilineTextAlignment(.center)
            Button("See in Activity") {
                session.selectedTab = .activity
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("import.seeActivity")
            Button("Import another statement") {
                rows = []
                fileURL = nil
                step = .choose
            }
            .accessibilityIdentifier("import.another")
        }
        .padding(UZSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("import.done")
    }
}

/// Edit one row before importing: payee, in or out, category and date.
struct ImportRowEditor: View {
    @Bindable var session: AppSession
    @Binding var row: ImportRow

    var body: some View {
        Form {
            Section {
                Toggle("Import this row", isOn: $row.include)
                Picker("Direction", selection: $row.isMoneyIn) {
                    Text("Money out").tag(false)
                    Text("Money in").tag(true)
                }
                .pickerStyle(.segmented)
                LabeledContent("Amount", value: MoneyFormatter.string(row.amount))
                TextField("Payee", text: $row.payee)
                NavigationLink {
                    CategoryPicker(categories: session.ledger.categories, type: row.isMoneyIn ? .income : .expense, selection: $row.categoryID)
                } label: {
                    LabeledContent("Category") { Text(session.ledger.categoryPath(row.categoryID) ?? "Choose") }
                }
                DatePicker("Date", selection: dateBinding, displayedComponents: .date)
            } footer: {
                Text("From the statement: \(row.description)")
            }
        }
        .navigationTitle(row.payee)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: row.isMoneyIn) {
            if let category = session.ledger.category(row.categoryID), category.type != (row.isMoneyIn ? .income : .expense) {
                row.categoryID = nil
            }
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { row.date.startDate(in: .current) }, set: { row.date = LocalDate($0, in: .current) })
    }
}
