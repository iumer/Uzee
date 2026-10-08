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

/// Statement import (SCR-34, J11): choose the account, pick a PDF or CSV, review, then import in one step with Undo.
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
    @State private var sourceName: String?
    @State private var currencyNote: String?
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
            .onAppear {
                if accountID == nil {
                    accountID = session.importAccountID.flatMap { id in ledger.activeAccounts.first { $0.id == id }?.id }
                        ?? ledger.activeAccounts.first?.id
                }
            }
        }
        .presentationDetents([.large])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("import.sheet")
    }

    // MARK: Step 1–2: account and file

    private var chooseStep: some View {
        Form {
            Section {
                Picker("Account", selection: $accountID) {
                    ForEach(ledger.activeAccounts) { account in
                        Text(account.currency == ledger.base ? account.name : "\(account.name) (\(account.currency.code))")
                            .tag(UUID?.some(account.id))
                    }
                }
                .accessibilityIdentifier("import.account")
            } header: {
                Text("Step 1 of 3 · Choose account")
            } footer: {
                Text("Rows are added to this account. Rows already in UZee are spotted and left out.")
            }
            Section {
                Button {
                    problem = nil
                    showingFiles = true
                } label: {
                    Label("Choose a PDF or CSV statement", systemImage: "doc.text")
                }
                .disabled(accountID == nil)
                .accessibilityIdentifier("import.pick")
                if let problem {
                    Text(problem).foregroundStyle(UZColor.negative)
                        .accessibilityIdentifier("import.problem")
                }
            } header: {
                Text("Step 2 of 3 · Pick the statement")
            } footer: {
                Text("Download the statement from your bank's app or website first. UZee reads it on this iPhone; nothing is uploaded.")
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
        guard let fileURL, let account else { return }
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
                let reading = StatementParser.read(versions: versions)
                review(reading, into: account)
            case .success(.csv(let text)):
                guard let reading = StatementParser.read(csv: text) else {
                    fail("UZee couldn't find dates and amounts in this CSV. Check it has Date and Amount (or Debit and Credit) columns.")
                    return
                }
                review(reading, into: account)
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

    private func review(_ reading: StatementReading, into account: Account) {
        guard !reading.rows.isEmpty else {
            if let source = reading.source {
                fail("This \(source.rawValue) statement has no transactions in it.")
            } else {
                fail("UZee can't read this bank's statement format yet. Share a sample statement so a reader can be added for this bank.")
            }
            return
        }
        let currency = account.currency
        let remembered = (try? session.activity.rememberedCategories()) ?? [:]
        var built: [ImportRow] = []
        var candidates: [DuplicateFinder.Candidate] = []
        for row in reading.rows {
            guard let magnitude = try? Money.fromMajor(abs(row.amount), currency), magnitude.minorUnits > 0 else { continue }
            let signed = row.amount < 0 ? ((try? magnitude.negated()) ?? magnitude) : magnitude
            candidates.append(DuplicateFinder.Candidate(date: row.date, amount: signed))
            let payee = StatementParser.payee(from: row.description)
            let type: CategoryType = row.amount > 0 ? .income : .expense
            let pickable = ledger.categories.filter { $0.type == type && !$0.isHidden }
            let category = CategorySuggester.suggest(payee: payee, remembered: remembered, categories: pickable)
                ?? CategorySuggester.suggest(payee: row.description, remembered: remembered, categories: pickable)
            built.append(ImportRow(id: built.count, date: row.date, description: row.description, payee: payee, amount: magnitude,
                                   isMoneyIn: row.amount > 0, categoryID: category, include: true, duplicateOf: nil))
        }
        let duplicates = DuplicateFinder.matches(candidates, accountID: account.id, in: session.transactions)
        rows = built.enumerated().map { index, row in
            guard let match = duplicates[index] else { return row }
            return ImportRow(id: row.id, date: row.date, description: row.description, payee: row.payee, amount: row.amount,
                             isMoneyIn: row.isMoneyIn, categoryID: row.categoryID, include: false, duplicateOf: match)
        }
        guessedSigns = reading.signSource == .words
        sourceName = reading.source?.rawValue
        if let code = reading.currencyCode, code != account.currency.code {
            currencyNote = "This statement is in \(code), but \(account.name) is in \(account.currency.code). Amounts are imported as they are, so choose a \(code) account if you have one."
        } else {
            currencyNote = nil
        }
        step = .review
    }

    // MARK: Step 3: review

    private var included: [ImportRow] { rows.filter(\.include) }

    private var reviewStep: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: UZSpacing.s) {
                    Text("\(rows.count) transactions found").font(.headline)
                    if let first = rows.map(\.date).min(), let last = rows.map(\.date).max() {
                        Text("\(DateText.long(first)) – \(DateText.long(last)) · into \(account?.name ?? "")")
                            .font(.subheadline).foregroundStyle(UZColor.label2)
                    }
                    if let sourceName {
                        Text("Read as a \(sourceName) statement").font(.footnote).foregroundStyle(UZColor.label2)
                    }
                    if let currencyNote {
                        Label(currencyNote, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(UZColor.warning)
                    }
                    if guessedSigns {
                        Label("This statement has no balance column, so money in and out was guessed from the words. Tap an amount to switch it.",
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(UZColor.warning)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("import.summary")
            } header: {
                Text("Step 3 of 3 · Review")
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
            .disabled(included.isEmpty)
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
        guard let account else { return }
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
