import SwiftUI
import UZeeCore

/// Add a shared expense the Splitwise way (owner, 2026-10-12): who it's with, what and how much, then one
/// sentence, "Paid by you and split equally", where each part opens its own choice. Save.
struct SharedExpenseSheet: View {
    @Bindable var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SplitDraft
    @State private var what = ""
    @State private var amountText = ""
    @State private var pickingCategory = false
    @State private var categoryID: UUID?
    @State private var suggestedCategoryID: UUID?
    @State private var remembered: [String: UUID]?
    @State private var accountID: UUID?
    /// The amount's currency, picked on the sign; your base currency to start. It never comes from an account
    /// you can't see: someone else paying hid "Paid from" and a dollar account turned 50,000 into $50,000 (owner, 2026-10-15).
    @State private var chosenCurrency: Currency
    @State private var date = Date()
    @State private var note = ""
    @State private var problem: String?
    @FocusState private var focus: Field?
    /// The shared expense being edited; saving changes it instead of adding another (owner, 2026-10-19).
    private var editing: MoneyTransaction?
    /// Set once saved, so a second tap while the sheet closes can't add it twice.
    @State private var didSave = false

    private enum Field { case what, amount }

    init(session: AppSession, group: UUID?, person: UUID?) {
        self.session = session
        let me = session.people.selfID
        var start = SplitDraft(participants: [me], payer: me)
        if let group = session.people.group(group) {
            start.groupID = group.id
            start.members = group.memberIDs.contains(me) ? group.memberIDs : [me] + group.memberIDs
            start.participants = start.members
            start.method = group.defaultMethod
        } else if let person {
            start.members = [me, person]
            start.participants = start.members
        }
        _draft = State(initialValue: start)
        let active = session.ledger.activeAccounts
        let last = try? session.client.lastUsedAccountID()
        let base = session.ledger.base
        let lastUsed = active.first { $0.id == last && $0.currency == base }
        _accountID = State(initialValue: lastUsed?.id ?? active.first { $0.currency == base }?.id ?? active.first?.id)
        _chosenCurrency = State(initialValue: base)
    }

    /// Edit a shared expense with the form it was made on: same people, amount and split, which can all change.
    init(session: AppSession, editing transaction: MoneyTransaction) {
        self.init(session: session, group: transaction.groupID, person: nil)
        editing = transaction
        if let split = session.people.split(for: transaction.id) { _draft = State(initialValue: SplitDraft(split)) }
        _what = State(initialValue: transaction.payeeName ?? "")
        _amountText = State(initialValue: MarkPaidSheet.plain(transaction.amount))
        _categoryID = State(initialValue: transaction.categoryID)
        _chosenCurrency = State(initialValue: transaction.amount.currency)
        _date = State(initialValue: transaction.occurredAt)
        _note = State(initialValue: transaction.note ?? "")
        if let account = transaction.legs.first(where: { $0.role == .main })?.accountID { _accountID = State(initialValue: account) }
    }

    /// "Add again today" on a shared expense: the same people, split and amount as a new expense, dated today.
    init(session: AppSession, copying transaction: MoneyTransaction) {
        self.init(session: session, editing: transaction)
        editing = nil
        _date = State(initialValue: Date())
    }

    private var me: UUID { session.people.selfID }
    private var ledger: LedgerSnapshot { session.ledger }
    private var hasPeople: Bool { draft.members.contains { $0 != me } }
    private var currency: Currency { youPaid ? (ledger.account(accountID)?.currency ?? chosenCurrency) : chosenCurrency }
    private var total: Money { (try? AmountParser.parse(amountText, currency: currency)) ?? .zero(currency) }
    /// You paid some or all of it, so money left one of your accounts.
    private var youPaid: Bool { draft.payer == me || (draft.payer == nil && (draft.paidAmounts[me] ?? 0) > 0) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    WithPeopleField(session: session, draft: $draft)
                }
                if hasPeople {
                    Section {
                        HStack(spacing: UZSpacing.l) {
                            categoryButton
                            TextField("What was it for?", text: $what)
                                .font(.title3)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textInputAutocapitalization(.sentences)
                                .focused($focus, equals: .what)
                                .submitLabel(.next)
                                .onSubmit { focus = .amount }
                                .onChange(of: what) { _, text in suggestCategory(text) }
                                .accessibilityIdentifier("shared.what")
                        }
                        HStack(spacing: UZSpacing.l) {
                            CurrencyMenu(ledger: ledger, currency: currency, size: 22) { choice in
                                chosenCurrency = choice
                                if ledger.account(accountID)?.currency != choice,
                                   let match = ledger.activeAccounts.first(where: { $0.currency == choice }) {
                                    accountID = match.id
                                }
                            }
                            .frame(minWidth: 44)
                            TextField("0", text: $amountText)
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .keyboardType(.decimalPad)
                                .monospacedDigit()
                                .focused($focus, equals: .amount)
                                // No live commas: rewriting the text while typing fast dropped the last digit (BUG-017).
                                .accessibilityIdentifier("shared.amount")
                        }
                    }
                    Section {
                        if let other = onlyOther {
                            // Owner, 2026-10-15: the three everyday cases in one tap.
                            Picker("Who owes", selection: Binding(get: { quick }, set: { setQuick($0, other: other) })) {
                                Text("Split equally").tag(Quick.equal)
                                Text("They owe all").tag(Quick.theyOweAll)
                                Text("I owe all").tag(Quick.iOweAll)
                                if quick == .custom { Text("Custom").tag(Quick.custom) }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("shared.quick")
                        }
                        SplitSentence(session: session, draft: $draft, total: total, isIncome: false)
                    } footer: {
                        SplitEffects(session: session, draft: draft, total: total, isIncome: false)
                    }
                    Section {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                            .accessibilityIdentifier("shared.date")
                        if youPaid {
                            Picker("Paid from", selection: $accountID) {
                                ForEach(ledger.activeAccounts) { account in
                                    Text(account.currency == ledger.base ? account.name : "\(account.name) (\(account.currency.code))")
                                        .tag(UUID?.some(account.id))
                                }
                            }
                            .accessibilityIdentifier("shared.account")
                        }
                        TextField("Note (optional)", text: $note, axis: .vertical)
                            .accessibilityIdentifier("shared.note")
                    } footer: {
                        Text(youPaid ? "Only your share counts as your spending." : "No money leaves your accounts; it's added to what you owe.")
                    }
                    if let problem {
                        Section {
                            Label(problem, systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(UZColor.negative)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(problem)
                                .accessibilityIdentifier("shared.problem")
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Add an expense" : "Edit expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { close() }
                        .accessibilityIdentifier("shared.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!hasPeople || total.minorUnits <= 0)
                        .accessibilityIdentifier("shared.save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }.fontWeight(.semibold)
                }
            }
            .navigationDestination(isPresented: $pickingCategory) {
                CategoryPicker(categories: ledger.categories, type: .expense, selection: $categoryID)
            }
            .onChange(of: hasPeople) { _, has in if has, what.isEmpty { focus = .what } }
            .onChange(of: draft) { problem = nil }
            .onChange(of: accountID) { _, id in if youPaid, let picked = ledger.account(id) { chosenCurrency = picked.currency } }
        }
        .presentationDetents([.large])
        .presentationSizing(.form)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shared.sheet")
    }

    /// The one other person, when it's just you and them (no group).
    private var onlyOther: UUID? {
        let others = draft.members.filter { $0 != me }
        return draft.groupID == nil && others.count == 1 ? others.first : nil
    }

    private enum Quick: Hashable { case equal, theyOweAll, iOweAll, custom }

    private var quick: Quick {
        guard let other = onlyOther else { return .custom }
        if draft.method == .equal, draft.payer == me, Set(draft.participants) == Set(draft.members) { return .equal }
        if draft.method == .shares, draft.payer == me, draft.inputs[me] == 0, (draft.inputs[other] ?? 0) > 0 { return .theyOweAll }
        if draft.method == .shares, draft.payer == other, draft.inputs[other] == 0, (draft.inputs[me] ?? 0) > 0 { return .iOweAll }
        return .custom
    }

    private func setQuick(_ choice: Quick, other: UUID) {
        switch choice {
        case .equal:
            draft.payer = me
            draft.method = .equal
            draft.participants = draft.members
            draft.inputs = [:]
        case .theyOweAll:
            draft.payer = me
            draft.method = .shares
            draft.participants = draft.members
            draft.inputs = [me: 0, other: 1]
        case .iOweAll:
            draft.payer = other
            draft.method = .shares
            draft.participants = draft.members
            draft.inputs = [me: 1, other: 0]
        case .custom:
            break
        }
        draft.paidAmounts = [:]
    }

    private var categoryButton: some View {
        // A button, not a NavigationLink: in a Form row a link adds a stray ">" and pushes the text field right.
        Button { pickingCategory = true } label: {
            let style = ledger.category(categoryID).map { CategoryStyle($0.group) }
            Image(systemName: style?.symbolName ?? "list.bullet")
                .font(.body.weight(.semibold))
                .foregroundStyle(style?.glyph ?? UZColor.label2)
                .frame(width: 44, height: 44)
                .background((style?.color ?? UZColor.label3).opacity(0.18), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ledger.categoryPath(categoryID) ?? "Choose a category")
        .accessibilityIdentifier("shared.category")
    }

    private func suggestCategory(_ text: String) {
        guard categoryID == nil || categoryID == suggestedCategoryID else { return }
        if remembered == nil { remembered = (try? session.activity.rememberedCategories()) ?? [:] }
        let pickable = ledger.categories.filter { $0.type == .expense }
        let suggestion = CategorySuggester.suggest(payee: text, remembered: remembered ?? [:], categories: pickable)
        categoryID = suggestion
        suggestedCategoryID = suggestion
    }

    /// "Other" when nothing was picked, so a quick split never stops on the category.
    private var fallbackCategory: UUID? {
        ledger.categories.first { $0.group == .other && $0.type == .expense && $0.parentID == nil && !$0.isHidden }?.id
    }

    private func save() {
        guard !didSave else { return }
        problem = nil
        let amount: Money
        do {
            amount = try AmountParser.parse(amountText, currency: currency)
        } catch {
            problem = ProblemText.message(error)
            focus = .amount
            return
        }
        guard !what.trimmingCharacters(in: .whitespaces).isEmpty else {
            problem = "Say what it was for, like “Dinner” or “Uber”."
            focus = .what
            return
        }
        // Someone else paid: no account moves, but the amount still needs a currency to be checked against.
        let checkedAccountID = youPaid ? accountID : ledger.activeAccounts.first { $0.currency == currency }?.id
        let transaction = TransactionDraft(
            kind: .expense, status: .posted, amount: amount, accountID: checkedAccountID, toAccountID: nil, receivedAmount: nil,
            categoryID: categoryID ?? fallbackCategory, payeeName: what.trimmingCharacters(in: .whitespaces), note: note,
            occurredAt: date, timeZone: editing.flatMap { TimeZone(identifier: $0.timeZoneID) } ?? .current,
            source: editing?.source ?? .manual)
        do {
            let built = try TransactionValidator.build(transaction, accounts: ledger.accounts, base: ledger.base, existing: editing)
            let split: Split
            do {
                split = try draft.build(total: built.amount, transactionID: built.id)
            } catch {
                problem = SplitText.problem(error)
                return
            }
            if session.save(built, split: split, isNew: editing == nil) {
                didSave = true
                close()
            }
        } catch {
            problem = ProblemText.message(error)
        }
    }

    private func close() {
        focus = nil
        dismiss()
        session.isAddPresented = false
    }
}

// MARK: - With you and…

/// "With you and:" then the chosen people as chips, and a search box with matching people, groups and
/// "Add as a new person" right below (Splitwise's first step).
struct WithPeopleField: View {
    @Bindable var session: AppSession
    @Binding var draft: SplitDraft
    @State private var query = ""
    @FocusState private var searching: Bool

    private var me: UUID { session.people.selfID }
    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var chosen: [UUID] { draft.members.filter { $0 != me } }

    var body: some View {
        VStack(alignment: .leading, spacing: UZSpacing.m) {
            Text("With you and:").font(.subheadline).foregroundStyle(UZColor.label2)
            FlowChips(spacing: UZSpacing.s) {
                if let group = session.people.group(draft.groupID) {
                    chip(group.name, systemImage: "person.3.fill") { clear() }
                        .accessibilityIdentifier("with.chip.\(group.name)")
                } else {
                    ForEach(chosen, id: \.self) { id in
                        let name = session.people.person(id)?.name ?? "Someone"
                        chip(name, systemImage: nil) { remove(id) }
                            .accessibilityIdentifier("with.chip.\(name)")
                    }
                }
                TextField(chosen.isEmpty ? "Name or group" : "Add more", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($searching)
                    .frame(minWidth: 120)
                    .onSubmit { if let first = matchingPeople.first { add(first.id) } else if !trimmed.isEmpty { addNew() } }
                    .accessibilityIdentifier("with.search")
            }
            if showsSuggestions {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(matchingGroups) { group in
                        suggestion(group.name, detail: memberLine(group)) { GroupTile(icon: group.icon, size: 30) } action: { pick(group) }
                            .accessibilityIdentifier("with.group.\(group.name)")
                    }
                    ForEach(matchingPeople) { person in
                        suggestion(person.name, detail: nil) { PersonAvatar(name: person.name, size: 30) } action: { add(person.id) }
                            .accessibilityIdentifier("with.person.\(person.name)")
                    }
                    if !trimmed.isEmpty && !session.people.others.contains(where: { NameKey.make($0.name) == NameKey.make(trimmed) }) {
                        suggestion("Add “\(trimmed)”", detail: "New person") {
                            Image(systemName: "person.crop.circle.badge.plus").font(.title2).foregroundStyle(UZColor.tint)
                                .frame(width: 30, height: 30)
                        } action: { addNew() }
                            .accessibilityIdentifier("with.addPerson")
                    }
                }
            }
        }
        .padding(.vertical, UZSpacing.xs)
        .onAppear { if chosen.isEmpty && draft.groupID == nil { searching = true } }
    }

    /// Suggestions show while typing, and before anyone is picked.
    private var showsSuggestions: Bool { !trimmed.isEmpty || (chosen.isEmpty && draft.groupID == nil) }

    private var matchingPeople: [Person] {
        Array(session.people.others
            .filter { $0.archivedAt == nil && !chosen.contains($0.id) && (trimmed.isEmpty || $0.name.localizedCaseInsensitiveContains(trimmed)) }
            .prefix(trimmed.isEmpty ? 6 : 8))
    }

    private var matchingGroups: [SplitGroup] {
        guard chosen.isEmpty else { return [] }
        return Array(session.people.groups
            .filter { $0.archivedAt == nil && $0.id != draft.groupID && (trimmed.isEmpty || $0.name.localizedCaseInsensitiveContains(trimmed)) }
            .prefix(4))
    }

    private func chip(_ name: String, systemImage: String?, remove: @escaping () -> Void) -> some View {
        HStack(spacing: UZSpacing.xs) {
            if let systemImage { Image(systemName: systemImage).font(.caption) } else { PersonAvatar(name: name, size: 22) }
            Text(name).font(.subheadline.weight(.medium)).lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(UZColor.label3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(name)")
        }
        .padding(.leading, UZSpacing.xs)
        .padding(.trailing, UZSpacing.s)
        .padding(.vertical, UZSpacing.xs)
        .background(UZColor.tint.opacity(0.12), in: .capsule)
    }

    private func suggestion<Icon: View>(_ title: String, detail: String?, @ViewBuilder icon: () -> Icon,
                                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: UZSpacing.l) {
                icon()
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).foregroundStyle(UZColor.label)
                    if let detail { Text(detail).font(.footnote).foregroundStyle(UZColor.label2) }
                }
                Spacer()
            }
            .padding(.vertical, UZSpacing.s)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func memberLine(_ group: SplitGroup) -> String {
        let names = group.memberIDs.filter { $0 != me }.compactMap { session.people.person($0)?.name }
        return (["you"] + names).joined(separator: ", ")
    }

    private func setMembers(_ others: [UUID], group: UUID? = nil) {
        draft.groupID = group
        draft.members = [me] + others
        draft.participants = draft.members
        draft.inputs = [:]
        draft.paidAmounts = [:]
        if let payer = draft.payer, !draft.members.contains(payer) { draft.payer = me }
    }

    private func add(_ id: UUID) {
        setMembers((draft.groupID == nil ? chosen : []) + [id])
        query = ""
    }

    private func remove(_ id: UUID) {
        setMembers(chosen.filter { $0 != id })
    }

    private func clear() {
        setMembers([])
        draft.method = .equal
    }

    private func pick(_ group: SplitGroup) {
        setMembers(group.memberIDs.filter { $0 != me }, group: group.id)
        draft.method = group.defaultMethod
        query = ""
        searching = false
    }

    private func addNew() {
        let name = trimmed
        var created: Person?
        if session.perform("Couldn't add \(name). Try again.", { created = try session.peopleClient.createPerson(name, nil) }),
           let created {
            add(created.id)
        }
    }
}

/// Lays chips out in rows, wrapping like text; the last view (the search box) takes the rest of its row.
struct FlowChips: Layout {
    var spacing: CGFloat = 6
    static let minimumLastWidth: CGFloat = 120

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for (index, view) in subviews.enumerated() {
            var size = view.sizeThatFits(.unspecified)
            if index == subviews.count - 1 { size.width = max(size.width, Self.minimumLastWidth) }
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += min(size.width, width) + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for (index, view) in subviews.enumerated() {
            let isLast = index == subviews.count - 1
            var size = view.sizeThatFits(.unspecified)
            if isLast { size.width = max(size.width, Self.minimumLastWidth) }
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            let width = isLast ? bounds.maxX - x : min(size.width, bounds.maxX - x)
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: width, height: size.height))
            x += width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Paid by … and split …

/// "Paid by you and split equally." Each underlined part opens its own short list (Splitwise's sentence).
struct SplitSentence: View {
    @Bindable var session: AppSession
    @Binding var draft: SplitDraft
    let total: Money
    let isIncome: Bool
    @State private var choosing: Choice?

    private enum Choice: String, Identifiable { case payer, split; var id: String { rawValue } }

    private var me: UUID { session.people.selfID }

    var body: some View {
        HStack(spacing: UZSpacing.xs) {
            Text(isIncome ? "Received by" : "Paid by")
            pill(payerText) { choosing = .payer }
                .accessibilityIdentifier("split.paidBy")
            Text("and split")
            pill(splitText) { choosing = .split }
                .accessibilityIdentifier("split.method")
        }
        .font(.body)
        .frame(maxWidth: .infinity)
        .sheet(item: $choosing) { choice in
            NavigationStack {
                switch choice {
                case .payer: PaidByView(session: session, draft: $draft, total: total, isIncome: isIncome)
                case .split: SplitHowView(session: session, draft: $draft, total: total, isIncome: isIncome)
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func pill(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.horizontal, UZSpacing.l)
                .padding(.vertical, UZSpacing.s)
                .background(UZColor.tint.opacity(0.14), in: .capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(UZColor.tint)
    }

    private var payerText: String {
        guard let payer = draft.payer else { return "2+ people" }
        return payer == me ? "you" : session.people.person(payer)?.name ?? "someone"
    }

    private var splitText: String {
        let others = draft.members.filter { $0 != me }
        if draft.method == .shares, others.count == 1, let other = others.first {
            if draft.inputs[me] == 0 && (draft.inputs[other] ?? 1) > 0 { return "they owe all" }
            if (draft.inputs[me] ?? 1) > 0 && draft.inputs[other] == 0 { return "you owe all" }
        }
        switch draft.method {
        case .equal: return draft.participants.count == draft.members.count ? "equally" : "equally (some)"
        case .exact: return "by amounts"
        case .percent: return "by %"
        case .shares: return "by shares"
        }
    }
}

/// Who paid: one tap on a name, or "several people" with amounts.
struct PaidByView: View {
    @Bindable var session: AppSession
    @Binding var draft: SplitDraft
    let total: Money
    let isIncome: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var texts: [UUID: String] = [:]
    @State private var several = false

    private var me: UUID { session.people.selfID }

    var body: some View {
        List {
            Section {
                ForEach(draft.members, id: \.self) { person in
                    Button {
                        draft.payer = person
                        draft.paidAmounts = [:]
                        dismiss()
                    } label: {
                        HStack(spacing: UZSpacing.l) {
                            PersonAvatar(name: name(person), size: 32)
                            Text(name(person)).foregroundStyle(UZColor.label)
                            Spacer()
                            if !several && draft.payer == person { Image(systemName: "checkmark").foregroundStyle(UZColor.tint).fontWeight(.semibold) }
                        }
                    }
                    .accessibilityIdentifier("paidBy.\(name(person))")
                }
                if draft.members.count > 2 {
                    Button {
                        several = true
                        draft.payer = nil
                        if draft.paidAmounts.isEmpty { draft.paidAmounts = [me: total.minorUnits] }
                        fill()
                    } label: {
                        HStack {
                            Text("Several people").foregroundStyle(UZColor.label)
                            Spacer()
                            if several { Image(systemName: "checkmark").foregroundStyle(UZColor.tint).fontWeight(.semibold) }
                        }
                    }
                    .accessibilityIdentifier("paidBy.several")
                }
            }
            if several {
                Section {
                    ForEach(draft.members, id: \.self) { person in
                        HStack {
                            Text(name(person))
                            Spacer()
                            Text(total.currency.symbol).foregroundStyle(UZColor.label2)
                            TextField("0", text: Binding(get: { texts[person] ?? "" }, set: { text in
                                texts[person] = text
                                draft.paidAmounts[person] = SplitEditorView.minor(text, total.currency)
                            }))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(maxWidth: 120)
                            .accessibilityIdentifier("paidBy.amount.\(name(person))")
                        }
                    }
                } footer: {
                    Text(paidLeft)
                }
            }
        }
        .navigationTitle(isIncome ? "Who received it?" : "Who paid?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) }
        }
        .onAppear {
            several = draft.payer == nil
            fill()
        }
    }

    private var paidLeft: String {
        let paid = draft.paidAmounts.values.reduce(Int64(0), +)
        let left = total.minorUnits - paid
        if left == 0 { return "Adds up to \(MoneyFormatter.string(total))." }
        let amount = MoneyFormatter.string(Money(minorUnits: abs(left), currency: total.currency))
        return left > 0 ? "\(amount) still to assign." : "\(amount) more than the total."
    }

    private func fill() {
        texts = [:]
        for (person, value) in draft.paidAmounts where value > 0 {
            texts[person] = plainNumber(Money(minorUnits: value, currency: total.currency))
        }
    }

    private func name(_ id: UUID) -> String {
        id == me ? "You" : session.people.person(id)?.name ?? "Someone"
    }
}

/// How to split: equally (tick who's in), exact amounts, percentages or shares. With one other person, the two
/// "owes the full amount" choices come first, as in Splitwise.
struct SplitHowView: View {
    @Bindable var session: AppSession
    @Binding var draft: SplitDraft
    let total: Money
    let isIncome: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var texts: [UUID: String] = [:]

    private var me: UUID { session.people.selfID }
    private var others: [UUID] { draft.members.filter { $0 != me } }

    var body: some View {
        List {
            if others.count == 1, let other = others.first {
                Section {
                    fullButton("\(name(other)) owes you the full \(MoneyFormatter.string(total))", payer: me, owes: other,
                               id: "split.full.them")
                    fullButton("You owe \(name(other)) the full \(MoneyFormatter.string(total))", payer: other, owes: me,
                               id: "split.full.you")
                }
            }
            Section {
                Picker("Split", selection: methodBinding) {
                    ForEach(SplitMethod.allCases, id: \.self) { Text(Self.short($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("split.methodPicker")
                ForEach(draft.members, id: \.self) { person in row(person) }
            } footer: {
                Text(footer)
            }
        }
        .navigationTitle("Split how?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("split.done")
            }
        }
        .onAppear(perform: fill)
    }

    static func short(_ method: SplitMethod) -> String {
        switch method {
        case .equal: "Equally"
        case .exact: "Amounts"
        case .percent: "%"
        case .shares: "Shares"
        }
    }

    private var methodBinding: Binding<SplitMethod> {
        Binding(get: { draft.method }, set: { method in
            draft.method = method
            draft.inputs = [:]
            draft.participants = draft.members
            fill()
        })
    }

    private func fullButton(_ title: String, payer: UUID, owes: UUID, id: String) -> some View {
        let on = draft.payer == payer && draft.method == .shares && draft.inputs[owes] == 1
            && draft.members.allSatisfy { $0 == owes || draft.inputs[$0] == 0 }
        return Button {
            draft.payer = payer
            draft.paidAmounts = [:]
            draft.method = .shares
            draft.participants = draft.members
            draft.inputs = Dictionary(draft.members.map { ($0, $0 == owes ? 1 : 0) }, uniquingKeysWith: { first, _ in first })
            dismiss()
        } label: {
            HStack {
                Text(title).foregroundStyle(UZColor.label)
                Spacer()
                if on { Image(systemName: "checkmark").foregroundStyle(UZColor.tint).fontWeight(.semibold) }
            }
        }
        .accessibilityIdentifier(id)
    }

    private func row(_ person: UUID) -> some View {
        let included = draft.participants.contains(person)
        let share = (try? draft.shares(total: total))?.first { $0.personID == person }?.share
        return HStack(spacing: UZSpacing.l) {
            PersonAvatar(name: name(person), size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(name(person))
                Text(share.map { MoneyFormatter.string($0) } ?? (included ? "" : "Not included"))
                    .font(.footnote).foregroundStyle(UZColor.label2).monospacedDigit()
            }
            Spacer()
            switch draft.method {
            case .equal:
                Button {
                    toggle(person)
                } label: {
                    Image(systemName: included ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(included ? UZColor.tint : UZColor.label3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(included ? "\(name(person)) included" : "\(name(person)) left out")
                .accessibilityIdentifier("split.include.\(name(person))")
            case .exact, .percent:
                if draft.method == .exact { Text(total.currency.symbol).foregroundStyle(UZColor.label2) }
                TextField("0", text: inputBinding(person))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 100)
                    .accessibilityIdentifier("split.value.\(name(person))")
                if draft.method == .percent { Text("%").foregroundStyle(UZColor.label2) }
            case .shares:
                let weight = draft.inputs[person] ?? 1
                Text("\(weight)").monospacedDigit().frame(minWidth: 24)
                Stepper("", onIncrement: { setWeight(person, weight + 1) }, onDecrement: { setWeight(person, max(0, weight - 1)) })
                    .labelsHidden()
                    .accessibilityLabel("\(name(person)) shares")
                    .accessibilityValue("\(weight)")
                    .accessibilityIdentifier("split.shares.\(name(person))")
            }
        }
    }

    private var footer: String {
        do {
            _ = try draft.build(total: total, transactionID: UUID())
        } catch {
            return SplitText.problem(error)
        }
        if draft.method == .equal {
            let count = Int64(max(1, draft.participants.count))
            return "\(MoneyFormatter.string(Money(minorUnits: total.minorUnits / count, currency: total.currency))) each"
        }
        return "Adds up to \(MoneyFormatter.string(total))."
    }

    private func toggle(_ person: UUID) {
        if let index = draft.participants.firstIndex(of: person) {
            guard draft.participants.count > 1 else { return }
            draft.participants.remove(at: index)
        } else {
            draft.participants = draft.members.filter { draft.participants.contains($0) || $0 == person }
        }
    }

    private func setWeight(_ person: UUID, _ weight: Int64) {
        draft.inputs[person] = weight
        draft.participants = draft.members
    }

    private func inputBinding(_ person: UUID) -> Binding<String> {
        Binding(get: { texts[person] ?? "" }, set: { text in
            texts[person] = text
            draft.participants = draft.members
            draft.inputs[person] = draft.method == .percent ? SplitEditorView.basisPoints(text) : SplitEditorView.minor(text, total.currency)
        })
    }

    private func fill() {
        texts = [:]
        for (person, value) in draft.inputs {
            switch draft.method {
            case .exact: texts[person] = plainNumber(Money(minorUnits: value, currency: total.currency))
            case .percent: texts[person] = SplitText.percent(value).replacingOccurrences(of: "%", with: "")
            default: break
            }
        }
    }

    private func name(_ id: UUID) -> String {
        id == me ? "You" : session.people.person(id)?.name ?? "Someone"
    }
}

/// "Usama owes you Rs 600" lines for this split alone, or what still needs fixing.
struct SplitEffects: View {
    @Bindable var session: AppSession
    let draft: SplitDraft
    let total: Money
    let isIncome: Bool

    private var me: UUID { session.people.selfID }

    var body: some View {
        VStack(alignment: .center, spacing: UZSpacing.xxs) {
            if total.minorUnits <= 0 {
                Text("Type the amount to see who owes what.")
            } else if let problem {
                Text(problem).foregroundStyle(UZColor.warning)
            } else {
                ForEach(lines, id: \.self) { line in
                    Text(line.text).fontWeight(.semibold).foregroundStyle(line.theyOwe ? UZColor.positive : UZColor.negative)
                }
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("split.effects")
    }

    private var problem: String? {
        do {
            _ = try draft.build(total: total, transactionID: UUID())
            return nil
        } catch {
            return SplitText.problem(error)
        }
    }

    struct Line: Hashable {
        let text: String
        let theyOwe: Bool
    }

    private var lines: [Line] { Self.lines(session: session, draft: draft, total: total, isIncome: isIncome) }

    /// "Usama owes you Rs 600" lines, also shown under Split on the Add screen.
    static func lines(session: AppSession, draft: SplitDraft, total: Money, isIncome: Bool) -> [Line] {
        let me = session.people.selfID
        guard let split = try? draft.build(total: total, transactionID: UUID()) else { return [] }
        var net: [UUID: Int64] = [:]
        for debt in SplitCalculator.debts(split, isIncome: isIncome) {
            if debt.creditor == me { net[debt.debtor, default: 0] += debt.amount.minorUnits }
            if debt.debtor == me { net[debt.creditor, default: 0] -= debt.amount.minorUnits }
        }
        let result: [Line] = draft.members.compactMap { person in
            guard let value = net[person], value != 0 else { return nil }
            let name = session.people.person(person)?.name ?? "Someone"
            let amount = MoneyFormatter.string(Money(minorUnits: abs(value), currency: total.currency))
            return value > 0 ? Line(text: "\(name) owes you \(amount)", theyOwe: true) : Line(text: "You owe \(name) \(amount)", theyOwe: false)
        }
        return result.isEmpty ? [Line(text: "Nobody owes anything for this one.", theyOwe: true)] : result
    }
}
