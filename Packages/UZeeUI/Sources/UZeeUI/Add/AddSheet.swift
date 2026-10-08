import PhotosUI
import SwiftUI
import UIKit
import UZeeCore

/// Add or edit a transaction (SCR-05, TXN-01…07). Amount first; account defaults to the last used one;
/// recent and everyday categories are one tap; Save saves, then "Saved · Undo" (AUD-13).
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
    /// Split with people or a group (SPL-03); nil = not split.
    @State private var splitDraft: SplitDraft?
    @State private var reviewSplit: Split?
    /// The edited transaction had a split, so saving without one removes it.
    @State private var hadSplit = false
    @State private var editing: MoneyTransaction?
    @State private var didLoad = false
    /// Receipt photo read on the device (AI-02); attached to the transaction when it is saved.
    @State private var receiptPhoto: Data?
    @State private var receiptNote: String?
    @State private var isReadingReceipt = false
    @State private var showingCamera = false
    @State private var showingPhotos = false
    @State private var photoItem: PhotosPickerItem?
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
            ScrollViewReader { proxy in
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
                                // Some toolchains read the symbol name as the label; say the message itself.
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(problem)
                                .accessibilityIdentifier("add.problem")
                        }
                        .id("problem")
                    }
                }
                // The message sits under the form; on iPad's shorter sheet it would be out of sight.
                .onChange(of: problem) { _, message in
                    guard message != nil else { return }
                    withAnimation { proxy.scrollTo("problem", anchor: .bottom) }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The number pad has no return key: Done hides it so Date, Note and Pending can be reached.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { amountFocused = false; hideKeyboard() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("add.keyboardDone")
                }
            }
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
            .onAppear(perform: load)
            .photosPicker(isPresented: $showingPhotos, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                Task {
                    let data = try? await item.loadTransferable(type: Data.self)
                    readReceipt(data)
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in readReceipt(image?.jpegData(compressionQuality: 0.9)) }
                    .ignoresSafeArea()
            }
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
                    .onChange(of: amountText) { _, typed in
                        let grouped = AmountTyping.grouped(typed)
                        if grouped != typed { amountText = grouped }
                    }
            }
            if kind != .transfer && editing == nil { scanRow }
        }
    }

    /// "Scan receipt": fills amount, date and shop from a photo, read on this iPhone (AI-02, J2 step 4).
    @ViewBuilder
    private var scanRow: some View {
        if isReadingReceipt {
            HStack(spacing: UZSpacing.m) {
                ProgressView()
                Text("Reading the receipt on this iPhone…").foregroundStyle(UZColor.label2)
            }
            .accessibilityIdentifier("add.readingReceipt")
        } else {
            Menu {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take photo", systemImage: "camera") { showingCamera = true }
                }
                Button("Choose photo", systemImage: "photo") { showingPhotos = true }
            } label: {
                Label(receiptPhoto == nil ? "Scan receipt" : "Scan another receipt", systemImage: "doc.text.viewfinder")
            }
            .accessibilityIdentifier("add.scanReceipt")
            if let receiptNote {
                Text(receiptNote).font(.footnote).foregroundStyle(UZColor.label2)
                    .accessibilityIdentifier("add.receiptNote")
            }
        }
    }

    private func readReceipt(_ data: Data?) {
        guard let data, let image = UIImage(data: data) else {
            session.errorMessage = "Couldn't read that photo. Try another one."
            return
        }
        let jpeg = image.resizedForReceipt().jpegData(compressionQuality: 0.8) ?? data
        receiptPhoto = jpeg
        isReadingReceipt = true
        let smart = session.smart
        let currency = currency
        let today = session.today
        Task {
            let pieces = await Task.detached { (try? smart.readReceipt(jpeg)) ?? [] }.value
            apply(ReceiptParser.read(pieces: pieces, currency: currency, today: today))
            isReadingReceipt = false
        }
    }

    private func apply(_ reading: ReceiptReading) {
        var filled: [String] = []
        let categoryBefore = categoryID
        if let amount = reading.amount {
            amountText = plainNumber(amount)
            filled.append("amount")
        }
        if let day = reading.date {
            let time = Calendar.current.dateComponents([.hour, .minute], from: Date())
            date = Calendar.current.date(byAdding: time, to: day.startDate(in: .current)) ?? day.startDate(in: .current)
            filled.append("date")
        }
        if let merchant = reading.merchant, payee.trimmingCharacters(in: .whitespaces).isEmpty {
            payee = merchant
            suggestCategory(for: merchant)
            filled.append("shop")
        }
        // The items can say more than the shop's name ("Ceramic coating wax" → Car maintenance).
        if categoryID == nil, let key = reading.categoryKey,
           let category = ledger.categories.first(where: { $0.systemKey == key && !$0.isHidden && $0.type == categoryType(for: kind) }) {
            categoryID = category.id
            suggestedCategoryID = category.id
        }
        if categoryID != nil, categoryID != categoryBefore { filled.append("category") }
        receiptNote = filled.isEmpty
            ? "Couldn't read this receipt. The photo will still be attached."
            : "Filled \(ListFormatter.localizedString(byJoining: filled)) from the receipt. Check them before saving. The photo will be attached."
    }

    private func attachReceipt(to transactionID: UUID) {
        guard let receiptPhoto else { return }
        if session.perform("Saved, but couldn't attach the receipt. Attach it from the transaction.", {
            _ = try session.activity.addAttachment(transactionID, .photo, receiptPhoto)
        }) {
            session.reload()
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
            if kind == .expense || kind == .income {
                NavigationLink {
                    SplitEditorView(session: session, total: currentTotal, isIncome: kind == .income, caption: splitCaption,
                                    draft: $splitDraft)
                } label: {
                    LabeledContent("Split") {
                        Text(splitSummary).foregroundStyle(splitDraft == nil ? UZColor.label2 : UZColor.label)
                    }
                }
                .accessibilityIdentifier("add.split")
            }
        }
    }

    private var currentTotal: Money {
        (try? AmountParser.parse(amountText, currency: currency)) ?? .zero(currency)
    }

    private var splitCaption: String {
        [payee.isEmpty ? nil : payee, ledger.categoryPath(categoryID)].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Office · your share Rs 1,600" or "Not split".
    private var splitSummary: String {
        guard let splitDraft else { return "Not split" }
        let me = session.people.selfID
        let with = session.people.group(splitDraft.groupID)?.name
            ?? splitDraft.members.filter { $0 != me }.compactMap { session.people.person($0)?.name }.joined(separator: ", ")
        guard let share = (try? splitDraft.shares(total: currentTotal))?.first(where: { $0.personID == me })?.share else { return with }
        return "\(with) · your share \(MoneyFormatter.string(share))"
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


    private func categoryType(for kind: TransactionKind) -> CategoryType {
        kind == .income ? .income : .expense
    }

    /// Up to six chips: categories used most recently for this type (TXN-010), topped up with everyday ones
    /// so a new user also gets one-tap categories.
    private var recentCategories: [SpendCategory] {
        var seen = Set<UUID>()
        var result: [SpendCategory] = []
        let type = categoryType(for: kind)
        for transaction in session.transactions where transaction.kind == kind {
            guard let id = transaction.categoryID, !seen.contains(id), let category = ledger.category(id),
                  category.type == type else { continue }
            seen.insert(id)
            result.append(category)
            if result.count == 4 { break }
        }
        let everyday = type == .income ? ["Salary", "Freelance / Business", "Reimbursement"]
                                       : ["Groceries", "Dining out", "Fuel", "Food delivery", "Ride-hailing", "Mobile"]
        for name in everyday where result.count < 6 && (kind == .expense || kind == .income) {
            guard let category = ledger.categories.first(where: { $0.name == name && $0.type == type && !$0.isHidden }),
                  !seen.contains(category.id) else { continue }
            seen.insert(category.id)
            result.append(category)
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
            splitDraft = session.people.split(for: transaction.id).map { SplitDraft($0) }
            hadSplit = splitDraft != nil
        case .repeatOf(let transaction):
            fill(from: transaction, keepDate: false)
            splitDraft = session.people.split(for: transaction.id).map { SplitDraft($0) }
        case .shared(let group, let person):
            accountID = defaultAccountID()
            amountFocused = true
            let me = session.people.selfID
            if let group = session.people.group(group) {
                var draft = SplitDraft(groupID: group.id, participants: group.memberIDs, method: group.defaultMethod, payer: me)
                draft.members = group.memberIDs
                splitDraft = draft
            } else if let person {
                splitDraft = SplitDraft(participants: [me, person], payer: me)
            }
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
        // Someone else paid: no account moves, but the amount still needs a currency to be checked against.
        let me = session.people.selfID
        let othersPaid = splitDraft.map { $0.payer != nil && $0.payer != me } ?? false
        let checkedAccountID = accountID ?? (othersPaid ? ledger.activeAccounts.first { $0.currency == currency }?.id : nil)
        let draft = TransactionDraft(
            kind: kind, status: isPending ? .pending : .posted, amount: amount, accountID: checkedAccountID,
            toAccountID: kind == .transfer ? toAccountID : nil, receivedAmount: received,
            categoryID: kind == .transfer ? nil : categoryID, payeeName: kind == .transfer ? nil : payee, note: note,
            occurredAt: date, timeZone: editing.flatMap { TimeZone(identifier: $0.timeZoneID) } ?? .current,
            source: editing?.source ?? .manual)
        do {
            let built = try TransactionValidator.build(draft, accounts: ledger.accounts, base: ledger.base, existing: editing)
            reviewSplit = nil
            if let splitDraft, kind == .expense || kind == .income {
                do {
                    reviewSplit = try splitDraft.build(total: built.amount, transactionID: built.id)
                } catch {
                    problem = SplitText.problem(error)
                    return
                }
            }
            commit(built)
        } catch {
            problem = ProblemText.message(error)
        }
    }

    /// Saves straight away; the toast's Undo takes it back (no second "Save this?" step).
    private func commit(_ transaction: MoneyTransaction) {
        let saved = reviewSplit != nil || hadSplit
            ? session.save(transaction, split: reviewSplit, isNew: editing == nil)
            : session.save(transaction, isNew: editing == nil)
        if saved {
            attachReceipt(to: transaction.id)
            session.isAddPresented = false
        }
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

/// Thousands separators while typing an amount: "2500" → "2,500", "1234567.5" → "1,234,567.5".
enum AmountTyping {
    static func grouped(_ text: String) -> String {
        let plain = text.filter { $0 != "," && !$0.isWhitespace }
        guard !plain.isEmpty, plain.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              plain.filter({ $0 == "." }).count <= 1 else { return text }
        let parts = plain.split(separator: ".", omittingEmptySubsequences: false)
        let whole = String(parts[0])
        // Leave leading zeros ("05") alone; they are being typed or corrected.
        guard whole.count > 3, !whole.hasPrefix("0") else { return text.contains(",") && whole.count <= 3 ? plain : text }
        var groups: [String] = []
        var rest = Substring(whole)
        while rest.count > 3 {
            groups.insert(String(rest.suffix(3)), at: 0)
            rest = rest.dropLast(3)
        }
        groups.insert(String(rest), at: 0)
        let joined = groups.joined(separator: ",")
        return parts.count > 1 ? joined + "." + parts[1] : joined
    }
}

private func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
