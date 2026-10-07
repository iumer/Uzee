import SwiftUI
import UZeeCore

/// Split editor (SCR-23, SPL-03…06/10): with whom, who paid, and how to split. Four quick choices cover
/// most cases; "More options" opens unequal amounts, percentages, shares and several payers.
/// Totals must add up before Done saves the split into the Add sheet (SPL-04).
struct SplitEditorView: View {
    @Bindable var session: AppSession
    let total: Money
    let isIncome: Bool
    let caption: String
    @Binding var draft: SplitDraft?
    @Environment(\.dismiss) private var dismiss
    @State private var working: SplitDraft
    @State private var texts: [UUID: String] = [:]
    @State private var paidTexts: [UUID: String] = [:]
    @State private var showsMore = false

    init(session: AppSession, total: Money, isIncome: Bool, caption: String, draft: Binding<SplitDraft?>) {
        self.session = session
        self.total = total
        self.isIncome = isIncome
        self.caption = caption
        _draft = draft
        let me = session.people.selfID
        let start = draft.wrappedValue ?? SplitDraft(participants: [me], payer: me)
        _working = State(initialValue: start)
        _showsMore = State(initialValue: start.method != .equal || start.payer == nil)
    }

    private var me: UUID { session.people.selfID }
    private var others: [UUID] { working.members.filter { $0 != me } }
    private var firstOther: UUID? { others.first }

    var body: some View {
        Form {
            Section {
                LabeledContent("Total amount") {
                    Text(MoneyFormatter.string(total)).font(.headline).monospacedDigit()
                }
                if !caption.isEmpty { Text(caption).font(.footnote).foregroundStyle(UZColor.label2) }
            }
            Section {
                NavigationLink {
                    SplitWithPicker(session: session, draft: $working)
                } label: {
                    LabeledContent("With") { Text(withSummary).foregroundStyle(others.isEmpty ? UZColor.label2 : UZColor.label) }
                }
                .accessibilityIdentifier("split.with")
            }
            if firstOther != nil {
                quickSection
                Section {
                    Toggle("More options", isOn: $showsMore.animation())
                        .accessibilityIdentifier("split.more")
                } footer: {
                    Text("Unequal amounts, %, shares, someone else from the list or several payers.")
                }
                if showsMore { moreSections }
                resultSection
            }
            if draft != nil {
                Section {
                    Button("Don't split", role: .destructive) {
                        draft = nil
                        dismiss()
                    }
                    .accessibilityIdentifier("split.remove")
                }
            }
        }
        .navigationTitle("Split")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    draft = others.isEmpty ? nil : working
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(!others.isEmpty && problem != nil)
                .accessibilityIdentifier("split.done")
            }
        }
        .onAppear(perform: fillTexts)
    }

    // MARK: Sections

    private var quickSection: some View {
        Section("Who paid, and how to split") {
            ForEach(QuickChoice.allCases, id: \.self) { choice in
                Button {
                    apply(choice)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(choice)).foregroundStyle(UZColor.label)
                            Text(line(choice)).font(.footnote).foregroundStyle(UZColor.label2)
                        }
                        Spacer()
                        if matches(choice) { Image(systemName: "checkmark").foregroundStyle(UZColor.tint).fontWeight(.semibold) }
                    }
                }
                .accessibilityIdentifier("split.quick.\(choice.rawValue)")
            }
        }
    }

    @ViewBuilder private var moreSections: some View {
        Section {
            Picker(isIncome ? "Received by" : "Paid by", selection: payerChoice) {
                ForEach(working.members, id: \.self) { Text(name($0)).tag(Optional($0)) }
                if working.members.count > 1 { Text("Several people").tag(UUID?.none) }
            }
            .accessibilityIdentifier("split.paidBy")
            Picker("Split", selection: $working.method) {
                ForEach(SplitMethod.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            .accessibilityIdentifier("split.method")
        }
        if working.payer == nil {
            Section(isIncome ? "Who received how much" : "Who paid how much") {
                ForEach(working.members, id: \.self) { person in
                    HStack {
                        PersonAvatar(name: name(person), size: 28)
                        Text(name(person))
                        Spacer()
                        Text(total.currency.symbol).foregroundStyle(UZColor.label2)
                        TextField("0", text: paidBinding(person))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(maxWidth: 110)
                            .accessibilityIdentifier("split.paid.\(name(person))")
                    }
                }
            }
        }
        Section(columnHeader) {
            ForEach(working.members, id: \.self) { person in memberRow(person) }
        }
    }

    private var resultSection: some View {
        Section {
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(UZColor.warning)
                    .accessibilityIdentifier("split.left")
            } else {
                Label("Adds up to \(MoneyFormatter.string(total))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(UZColor.positive)
                    .accessibilityIdentifier("split.left")
            }
            LabeledContent("Your share") {
                Text(myShare.map { MoneyFormatter.string($0) } ?? "—").font(.headline).monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("split.myShare")
            ForEach(effects, id: \.self) { Text($0).font(.subheadline).foregroundStyle(UZColor.label2) }
        } footer: {
            Text(isIncome ? "Only your share counts as your income." : "Only your share counts toward your budget.")
        }
    }

    private func memberRow(_ person: UUID) -> some View {
        let included = working.participants.contains(person)
        let share = (try? working.shares(total: total))?.first { $0.personID == person }?.share
        return HStack(spacing: UZSpacing.l) {
            PersonAvatar(name: name(person), size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(name(person))
                Text(share.map { MoneyFormatter.string($0) } ?? (included ? "" : "Not included"))
                    .font(.footnote).foregroundStyle(UZColor.label2).monospacedDigit()
            }
            Spacer()
            switch working.method {
            case .equal:
                Button {
                    toggle(person)
                } label: {
                    Image(systemName: included ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(included ? UZColor.tint : UZColor.label2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(included ? "\(name(person)) included" : "\(name(person)) left out")
                .accessibilityIdentifier("split.include.\(name(person))")
            case .exact, .percent:
                if working.method == .exact { Text(total.currency.symbol).foregroundStyle(UZColor.label2) }
                TextField("0", text: inputBinding(person))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 100)
                    .accessibilityIdentifier("split.value.\(name(person))")
                if working.method == .percent { Text("%").foregroundStyle(UZColor.label2) }
            case .shares:
                let weight = working.inputs[person] ?? 1
                Text("\(weight)").monospacedDigit().frame(minWidth: 24)
                Stepper("", onIncrement: { setWeight(person, weight + 1) }, onDecrement: { setWeight(person, max(0, weight - 1)) })
                    .labelsHidden()
                    .accessibilityLabel("\(name(person)) shares")
                    .accessibilityValue("\(weight)")
                    .accessibilityIdentifier("split.shares.\(name(person))")
            }
        }
    }

    // MARK: Quick choices (Splitwise's four)

    enum QuickChoice: String, CaseIterable {
        case youPaidEqual, youPaidTheyOwe, theyPaidEqual, theyPaidYouOwe
    }

    private func title(_ choice: QuickChoice) -> String {
        let other = firstOther.map(name) ?? "They"
        let paid = isIncome ? "received" : "paid"
        let many = others.count > 1
        switch choice {
        case .youPaidEqual: return "You \(paid), split equally"
        case .youPaidTheyOwe: return many ? "You \(paid), the others owe it all" : "You \(paid), \(other) owes it all"
        case .theyPaidEqual: return "\(other) \(paid), split equally"
        case .theyPaidYouOwe: return "\(other) \(paid), you owe it all"
        }
    }

    private func line(_ choice: QuickChoice) -> String {
        guard let other = firstOther else { return "" }
        let count = Int64(working.members.count)
        let each = Money(minorUnits: total.minorUnits / max(1, count), currency: total.currency)
        let rest = Money(minorUnits: total.minorUnits - each.minorUnits, currency: total.currency)
        switch choice {
        case .youPaidEqual: return others.count > 1 ? "Each owes you \(MoneyFormatter.string(each))" : "\(name(other)) owes you \(MoneyFormatter.string(each))"
        case .youPaidTheyOwe: return "You are owed \(MoneyFormatter.string(total))"
        case .theyPaidEqual: return "You owe \(name(other)) \(MoneyFormatter.string(each))" + (others.count > 1 ? " · others owe \(MoneyFormatter.string(rest))" : "")
        case .theyPaidYouOwe: return "You owe \(name(other)) \(MoneyFormatter.string(total))"
        }
    }

    private func apply(_ choice: QuickChoice) {
        guard let other = firstOther else { return }
        working.participants = working.members
        working.paidAmounts = [:]
        switch choice {
        case .youPaidEqual:
            working.payer = me
            working.method = .equal
            working.inputs = [:]
        case .youPaidTheyOwe:
            working.payer = me
            working.method = .shares
            working.inputs = Dictionary(uniqueKeysWithValues: working.members.map { ($0, $0 == me ? 0 : 1) })
        case .theyPaidEqual:
            working.payer = other
            working.method = .equal
            working.inputs = [:]
        case .theyPaidYouOwe:
            working.payer = other
            working.method = .shares
            working.inputs = Dictionary(uniqueKeysWithValues: working.members.map { ($0, $0 == me ? 1 : 0) })
        }
        fillTexts()
    }

    private func matches(_ choice: QuickChoice) -> Bool {
        guard let other = firstOther, working.participants == working.members else { return false }
        let meOnly = working.method == .shares && working.inputs[me] == 1 && others.allSatisfy { (working.inputs[$0] ?? 1) == 0 }
        let othersOnly = working.method == .shares && working.inputs[me] == 0 && others.allSatisfy { (working.inputs[$0] ?? 1) == 1 }
        switch choice {
        case .youPaidEqual: return working.payer == me && working.method == .equal
        case .youPaidTheyOwe: return working.payer == me && othersOnly
        case .theyPaidEqual: return working.payer == other && working.method == .equal
        case .theyPaidYouOwe: return working.payer == other && meOnly
        }
    }

    // MARK: Values

    private var payerChoice: Binding<UUID?> {
        Binding(get: { working.payer }, set: { newValue in
            working.payer = newValue
            if newValue == nil && working.paidAmounts.isEmpty { working.paidAmounts = [me: total.minorUnits] ; fillTexts() }
        })
    }

    private func toggle(_ person: UUID) {
        if let index = working.participants.firstIndex(of: person) {
            guard working.participants.count > 1 else { return }
            working.participants.remove(at: index)
        } else {
            working.participants = working.members.filter { working.participants.contains($0) || $0 == person }
        }
    }

    private func setWeight(_ person: UUID, _ weight: Int64) {
        working.inputs[person] = weight
        working.participants = working.members
    }

    private func inputBinding(_ person: UUID) -> Binding<String> {
        Binding(get: { texts[person] ?? "" }, set: { text in
            texts[person] = text
            working.participants = working.members
            working.inputs[person] = working.method == .percent ? Self.basisPoints(text) : Self.minor(text, total.currency)
        })
    }

    private func paidBinding(_ person: UUID) -> Binding<String> {
        Binding(get: { paidTexts[person] ?? "" }, set: { text in
            paidTexts[person] = text
            working.paidAmounts[person] = Self.minor(text, total.currency)
        })
    }

    /// Shows the stored inputs as text when the editor opens or a quick choice resets them.
    private func fillTexts() {
        texts = [:]
        paidTexts = [:]
        for (person, value) in working.inputs {
            switch working.method {
            case .exact: texts[person] = plainNumber(Money(minorUnits: value, currency: total.currency))
            case .percent: texts[person] = SplitText.percent(value).replacingOccurrences(of: "%", with: "")
            default: break
            }
        }
        for (person, value) in working.paidAmounts where value > 0 {
            paidTexts[person] = plainNumber(Money(minorUnits: value, currency: total.currency))
        }
    }

    static func minor(_ text: String, _ currency: Currency) -> Int64 {
        (try? AmountParser.parse(text, currency: currency))?.minorUnits ?? 0
    }

    static func basisPoints(_ text: String) -> Int64 {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { return 0 }
        return Rounding.int64(Rounding.halfUp(value * 100, scale: 0)) ?? 0
    }

    // MARK: Results

    private var problem: String? {
        do {
            _ = try working.build(total: total, transactionID: UUID())
            return nil
        } catch {
            return SplitText.problem(error)
        }
    }

    private var myShare: Money? {
        (try? working.shares(total: total))?.first { $0.personID == me }?.share ?? .zero(total.currency)
    }

    /// "Office partner owes you Rs 30,000" lines from this split alone.
    private var effects: [String] {
        guard let split = try? working.build(total: total, transactionID: UUID()) else { return [] }
        var net: [UUID: Int64] = [:]
        for debt in SplitCalculator.debts(split, isIncome: isIncome) {
            if debt.creditor == me { net[debt.debtor, default: 0] += debt.amount.minorUnits }
            if debt.debtor == me { net[debt.creditor, default: 0] -= debt.amount.minorUnits }
        }
        return working.members.compactMap { person in
            guard let value = net[person], value != 0 else { return nil }
            let amount = MoneyFormatter.string(Money(minorUnits: abs(value), currency: total.currency))
            return value > 0 ? "\(name(person)) owes you \(amount)" : "You owe \(name(person)) \(amount)"
        }
    }

    private var withSummary: String {
        if let group = session.people.group(working.groupID) { return group.name }
        let names = others.map(name)
        return names.isEmpty ? "Choose people or a group" : names.joined(separator: ", ")
    }

    private var columnHeader: String {
        switch working.method {
        case .equal: "Split equally between"
        case .exact: "Exact amounts"
        case .percent: "Percentages"
        case .shares: "Shares"
        }
    }

    private func name(_ id: UUID) -> String {
        id == me ? "You" : session.people.person(id)?.name ?? "Someone"
    }
}

/// Choose a group or people to split with (SCR-23 picker); add a new person by name.
struct SplitWithPicker: View {
    @Bindable var session: AppSession
    @Binding var draft: SplitDraft
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var me: UUID { session.people.selfID }
    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        List {
            let groups = session.people.groups.filter { $0.archivedAt == nil && matches($0.name) }
            if !groups.isEmpty {
                Section("Groups") {
                    ForEach(groups) { group in
                        Button {
                            draft.groupID = group.id
                            draft.members = group.memberIDs.contains(me) ? group.memberIDs : [me] + group.memberIDs
                            draft.participants = draft.members
                            draft.method = group.defaultMethod
                            if let payer = draft.payer, !draft.members.contains(payer) { draft.payer = me }
                            dismiss()
                        } label: {
                            HStack(spacing: UZSpacing.l) {
                                GroupTile(icon: group.icon, size: 32)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(group.name).foregroundStyle(UZColor.label)
                                    Text(memberLine(group)).font(.footnote).foregroundStyle(UZColor.label2)
                                }
                                Spacer()
                                if draft.groupID == group.id { Image(systemName: "checkmark").foregroundStyle(UZColor.tint) }
                            }
                        }
                        .accessibilityIdentifier("pick.group.\(group.name)")
                    }
                }
            }
            Section("People") {
                ForEach(session.people.others.filter { $0.archivedAt == nil && matches($0.name) }) { person in
                    Button {
                        togglePerson(person.id)
                    } label: {
                        HStack(spacing: UZSpacing.l) {
                            PersonAvatar(name: person.name, size: 32)
                            Text(person.name).foregroundStyle(UZColor.label)
                            Spacer()
                            if draft.groupID == nil && draft.members.contains(person.id) {
                                Image(systemName: "checkmark").foregroundStyle(UZColor.tint)
                            }
                        }
                    }
                    .accessibilityIdentifier("pick.person.\(person.name)")
                }
                if !trimmed.isEmpty && !session.people.others.contains(where: { NameKey.make($0.name) == NameKey.make(trimmed) }) {
                    Button("Add “\(trimmed)” as a new person", systemImage: "plus.circle.fill") { addPerson() }
                        .accessibilityIdentifier("pick.addPerson")
                }
            }
        }
        .searchable(text: $query, prompt: "Name or group")
        .navigationTitle("Split with")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func matches(_ name: String) -> Bool {
        trimmed.isEmpty || name.localizedCaseInsensitiveContains(trimmed)
    }

    private func memberLine(_ group: SplitGroup) -> String {
        let names = group.memberIDs.filter { $0 != me }.compactMap { session.people.person($0)?.name }
        return (["you"] + names).joined(separator: ", ")
    }

    private func togglePerson(_ id: UUID) {
        var chosen = draft.groupID == nil ? draft.members.filter { $0 != me } : []
        if let index = chosen.firstIndex(of: id) { chosen.remove(at: index) } else { chosen.append(id) }
        draft.groupID = nil
        draft.members = [me] + chosen
        draft.participants = draft.members
        if let payer = draft.payer, !draft.members.contains(payer) { draft.payer = me }
    }

    private func addPerson() {
        var created: Person?
        if session.perform("Couldn't add \(trimmed). Try again.", { created = try session.peopleClient.createPerson(trimmed, nil) }),
           let created {
            query = ""
            togglePerson(created.id)
        }
    }
}
