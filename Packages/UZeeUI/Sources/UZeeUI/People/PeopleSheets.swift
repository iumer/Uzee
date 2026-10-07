import SwiftUI
import UIKit
import UZeeCore

/// Add or edit a person (LOAN-01): name and optional phone.
struct PersonFormSheet: View {
    @Bindable var session: AppSession
    let editing: Person?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var problem: String?
    @State private var showsExisting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("personForm.name")
                    TextField("Phone (optional)", text: $phone)
                        .keyboardType(.phonePad)
                        .accessibilityIdentifier("personForm.phone")
                } footer: {
                    if editing == nil { Text("Starts with no balance. Already owe each other money? Add existing balances instead.") }
                }
                if editing == nil {
                    Section {
                        Button("Add existing balances instead") { showsExisting = true }
                    }
                }
                if let problem {
                    Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(UZColor.negative) }
                }
            }
            .navigationTitle(editing == nil ? "Add person" : "Edit person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save", action: save)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("personForm.save")
                }
            }
            .onAppear {
                if let editing, name.isEmpty {
                    name = editing.name
                    phone = editing.phone ?? ""
                }
            }
            .sheet(isPresented: $showsExisting) { ExistingBalancesSheet(session: session, firstName: name) }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        do {
            _ = try Person.validateName(name)
        } catch {
            problem = error == .emptyName ? "Enter a name." : "Use 60 characters or fewer."
            return
        }
        let cleanPhone = phone.trimmingCharacters(in: .whitespaces)
        let ok = session.perform("Couldn't save. Try again.") {
            if var person = editing {
                person.name = name
                person.phone = cleanPhone.isEmpty ? nil : cleanPhone
                try session.peopleClient.updatePerson(person)
            } else {
                _ = try session.peopleClient.createPerson(name, cleanPhone.isEmpty ? nil : cleanPhone)
            }
        }
        if ok {
            session.toasts.show(editing == nil ? "\(name.trimmingCharacters(in: .whitespaces)) added" : "Saved")
            dismiss()
        }
    }
}

/// Existing balances (LOAN-08): one row per person, opening balances with no account movement.
struct ExistingBalancesSheet: View {
    @Bindable var session: AppSession
    var firstName = ""
    @Environment(\.dismiss) private var dismiss

    struct Row: Identifiable {
        let id = UUID()
        var name = ""
        var owesYou = true
        var amount = ""
    }

    @State private var rows: [Row] = [Row()]
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("One row per person. These are opening balances: no account money moves.")
                        .font(.footnote).foregroundStyle(UZColor.label2)
                }
                ForEach($rows) { $row in
                    Section {
                        TextField("Name", text: $row.name)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("existing.name")
                        Picker("Direction", selection: $row.owesYou) {
                            Text("Owes you").tag(true)
                            Text("You owe").tag(false)
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            Text(session.ledger.base.symbol).foregroundStyle(UZColor.label2)
                            TextField("0", text: $row.amount)
                                .keyboardType(.decimalPad)
                                .monospacedDigit()
                                .accessibilityIdentifier("existing.amount")
                        }
                        if rows.count > 1 {
                            Button("Remove", role: .destructive) { rows.removeAll { $0.id == row.id } }
                        }
                    }
                }
                Section {
                    Button("Add another person", systemImage: "plus") { rows.append(Row()) }
                } footer: {
                    Text("“Owes you” means they will pay you back. Matching names add to that person's balance.")
                }
                if let problem {
                    Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(UZColor.negative) }
                }
            }
            .navigationTitle("Existing balances")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold).accessibilityIdentifier("existing.save")
                }
            }
            .onAppear { if rows.count == 1 && rows[0].name.isEmpty { rows[0].name = firstName } }
        }
    }

    private func save() {
        var parsed: [PeopleClient.BalanceRow] = []
        for row in rows where !row.name.trimmingCharacters(in: .whitespaces).isEmpty || !row.amount.isEmpty {
            guard (try? Person.validateName(row.name)) != nil else { problem = "Enter a name on every row."; return }
            guard let amount = try? AmountParser.parse(row.amount, currency: session.ledger.base), amount.minorUnits > 0 else {
                problem = "Enter an amount for \(row.name)."
                return
            }
            parsed.append((name: row.name, direction: row.owesYou ? LoanDirection.lent : .borrowed, amount: amount))
        }
        guard !parsed.isEmpty else { problem = "Add at least one person."; return }
        if session.perform("Couldn't save. Nothing was changed. Try again.", { try session.peopleClient.addExistingBalances(parsed) }) {
            session.toasts.show(parsed.count == 1 ? "Balance added" : "\(parsed.count) balances added")
            dismiss()
        }
    }
}

/// New or edited group (SPL-02): name, icon, members ("You" always included) and default split.
struct GroupFormSheet: View {
    @Bindable var session: AppSession
    let editing: SplitGroup?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon: GroupIcon = .people
    @State private var members: [UUID] = []
    @State private var method: SplitMethod = .equal
    @State private var simplify = true
    @State private var newName = ""
    @State private var problem: String?
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Office, Trip to Hunza, Home", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("groupForm.name")
                }
                Section("Icon") {
                    HStack {
                        ForEach(GroupIcon.allCases, id: \.self) { option in
                            Button {
                                icon = option
                            } label: {
                                VStack(spacing: 4) {
                                    GroupTile(icon: option, size: 36)
                                        .overlay { if icon == option { RoundedRectangle(cornerRadius: 12).stroke(UZColor.tint, lineWidth: 2.5).padding(-3) } }
                                    Text(option.label).font(.caption2).foregroundStyle(UZColor.label2)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.label)
                            .accessibilityAddTraits(icon == option ? .isSelected : [])
                        }
                    }
                }
                Section {
                    LabeledContent("You", value: "always included")
                    ForEach(session.people.others.filter { $0.archivedAt == nil }) { person in
                        Button {
                            if let index = members.firstIndex(of: person.id) { members.remove(at: index) } else { members.append(person.id) }
                        } label: {
                            HStack {
                                PersonAvatar(name: person.name, size: 28)
                                Text(person.name).foregroundStyle(UZColor.label)
                                Spacer()
                                if members.contains(person.id) { Image(systemName: "checkmark").foregroundStyle(UZColor.tint) }
                            }
                        }
                        .accessibilityIdentifier("groupForm.member.\(person.name)")
                    }
                    HStack {
                        TextField("Add a new person", text: $newName)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("groupForm.newPerson")
                        Button("Add") { addPerson() }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Members · you are always included")
                }
                Section {
                    Picker("Default split", selection: $method) {
                        ForEach(SplitMethod.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    Toggle("Simplify debts", isOn: $simplify)
                } footer: {
                    Text("Simplify debts nets balances so fewer payments are needed (groups of three or more).")
                }
                if let problem {
                    Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(UZColor.negative) }
                }
            }
            .navigationTitle(editing == nil ? "New group" : "Edit group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Create" : "Save", action: save).fontWeight(.semibold).accessibilityIdentifier("groupForm.save")
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let editing else { return }
        name = editing.name
        icon = editing.icon
        members = editing.memberIDs.filter { $0 != session.people.selfID }
        method = editing.defaultMethod
        simplify = editing.simplifyDebts
    }

    private func addPerson() {
        var created: Person?
        if session.perform("Couldn't add that person. Try again.", { created = try session.peopleClient.createPerson(newName, nil) }),
           let created {
            members.append(created.id)
            newName = ""
        }
    }

    private func save() {
        guard (try? Person.validateName(name)) != nil else { problem = "Enter a group name."; return }
        guard !members.isEmpty else { problem = "Choose at least one other member."; return }
        let ok = session.perform("Couldn't save the group. Try again.") {
            if var group = editing {
                group.name = name
                group.icon = icon
                group.memberIDs = [session.people.selfID] + members
                group.defaultMethod = method
                group.simplifyDebts = simplify
                try session.peopleClient.updateGroup(group)
            } else {
                var group = try session.peopleClient.createGroup(name, icon, members, method)
                if !simplify {
                    group.simplifyDebts = false
                    try session.peopleClient.updateGroup(group)
                }
            }
        }
        if ok {
            session.toasts.show(editing == nil ? "Group created" : "Group saved")
            dismiss()
        }
    }
}

/// Lend or borrow (LOAN-05): the account transaction and the loan together. "No account" records an
/// existing balance (LOAN-08).
struct LoanSheet: View {
    @Bindable var session: AppSession
    let personID: UUID
    @State var direction: LoanDirection
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var accountID: UUID?
    @State private var date = Date()
    @State private var hasDue = false
    @State private var due = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var note = ""
    @State private var problem: String?
    @State private var didLoad = false

    private var name: String { session.people.person(personID)?.name ?? "them" }
    private var currency: Currency { session.ledger.account(accountID)?.currency ?? session.ledger.base }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $direction) {
                        Text("Lend to \(name)").tag(LoanDirection.lent)
                        Text("Borrow from \(name)").tag(LoanDirection.borrowed)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("loan.type")
                    HStack {
                        Text(currency.symbol).font(.title.bold()).foregroundStyle(UZColor.label2)
                        TextField("0", text: $amount)
                            .font(.title.bold())
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                            .accessibilityIdentifier("loan.amount")
                    }
                }
                Section {
                    Picker(direction == .lent ? "From" : "Into", selection: $accountID) {
                        Text("No account · existing balance").tag(UUID?.none)
                        ForEach(session.ledger.activeAccounts) { account in
                            Text(account.name).tag(UUID?.some(account.id))
                        }
                    }
                    .accessibilityIdentifier("loan.account")
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Toggle("Due date", isOn: $hasDue)
                    if hasDue { DatePicker("Due", selection: $due, displayedComponents: .date) }
                    TextField("Note", text: $note)
                } footer: {
                    Text(accountID == nil ? "No account money moves. Use this for money already lent or borrowed."
                                          : "Not spending or income. \(name)'s balance updates.")
                }
                if let problem {
                    Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(UZColor.negative) }
                }
            }
            .navigationTitle(direction == .lent ? "Lend" : "Borrow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold).accessibilityIdentifier("loan.save")
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                accountID = session.ledger.activeAccounts.first?.id
            }
        }
    }

    private func save() {
        let money: Money
        do {
            money = try AmountParser.parse(amount, currency: currency)
            guard money.minorUnits > 0 else { problem = "The amount must be more than zero."; return }
        } catch {
            problem = ProblemText.message(error)
            return
        }
        let dueDate = hasDue ? LocalDate(due, in: .current) : nil
        let text = note.trimmingCharacters(in: .whitespaces)
        if session.perform("Couldn't save. Nothing was changed. Try again.", {
            try session.peopleClient.recordLoan(direction, personID, money, accountID, date, dueDate, text.isEmpty ? nil : text)
        }) {
            session.toasts.show(direction == .lent ? "Lent \(MoneyFormatter.string(money)) to \(name)" : "Borrowed \(MoneyFormatter.string(money))")
            dismiss()
        }
    }
}

/// Record a repayment (LOAN-03) into or out of an account.
struct RepaymentSheet: View {
    @Bindable var session: AppSession
    let loanID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var accountID: UUID?
    @State private var date = Date()
    @State private var problem: String?
    @State private var didLoad = false

    private var loan: Loan? { session.people.loans.first { $0.id == loanID } }

    var body: some View {
        NavigationStack {
            Form {
                if let loan {
                    let name = session.people.person(loan.personID)?.name ?? "them"
                    Section {
                        LabeledContent(loan.direction == .lent ? "\(name) owes you" : "You owe \(name)",
                                       value: MoneyFormatter.string(LoanCalculator.outstanding(loan)))
                        HStack {
                            Text(loan.principal.currency.symbol).font(.title.bold()).foregroundStyle(UZColor.label2)
                            TextField("0", text: $amount)
                                .font(.title.bold())
                                .keyboardType(.decimalPad)
                                .monospacedDigit()
                                .accessibilityIdentifier("repay.amount")
                        }
                    }
                    Section {
                        Picker(loan.direction == .lent ? "Into" : "From", selection: $accountID) {
                            ForEach(session.ledger.activeAccounts.filter { $0.currency == loan.principal.currency }) { account in
                                Text(account.name).tag(UUID?.some(account.id))
                            }
                        }
                        .accessibilityIdentifier("repay.account")
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                    } footer: {
                        Text("Not spending or income. The loan's balance goes down.")
                    }
                }
                if let problem {
                    Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(UZColor.negative) }
                }
            }
            .navigationTitle("Record repayment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold).accessibilityIdentifier("repay.save")
                }
            }
            .onAppear {
                guard !didLoad, let loan else { return }
                didLoad = true
                amount = plainNumber(LoanCalculator.outstanding(loan))
                accountID = session.ledger.activeAccounts.first { $0.currency == loan.principal.currency }?.id
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let loan else { return }
        guard let accountID else { problem = "Choose an account."; return }
        let money: Money
        do {
            money = try AmountParser.parse(amount, currency: loan.principal.currency)
            try LoanCalculator.validatePayment(money, for: loan)
        } catch let error as LoanCalculator.Problem {
            switch error {
            case .moreThanOutstanding(let left): problem = "That's more than the \(MoneyFormatter.string(left)) left."
            case .writtenOff: problem = "This loan was written off."
            case .invalidAmount: problem = "The amount must be more than zero."
            }
            return
        } catch let error as AmountParser.Failure {
            problem = ProblemText.message(error)
            return
        } catch {
            problem = "Check the amount."
            return
        }
        if session.perform("Couldn't save. Nothing was changed. Try again.", {
            try session.peopleClient.recordRepayment(loan.id, money, accountID, date)
        }) {
            session.toasts.show("Repayment saved")
            dismiss()
        }
    }
}

/// Due date and optional simple interest for a loan (LOAN-02).
struct LoanTermsSheet: View {
    @Bindable var session: AppSession
    let loanID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var hasDue = false
    @State private var due = Date()
    @State private var rate = ""
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Due date", isOn: $hasDue)
                    if hasDue { DatePicker("Due", selection: $due, displayedComponents: .date) }
                }
                Section {
                    HStack {
                        Text("Rate per year")
                        Spacer()
                        TextField("0", text: $rate).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 80)
                        Text("%").foregroundStyle(UZColor.label2)
                    }
                } header: {
                    Text("Interest (optional)")
                } footer: {
                    Text("Simple interest, shown for information. It isn't added to the balance.")
                }
            }
            .navigationTitle("Loan details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.semibold) }
            }
            .onAppear {
                guard !didLoad, let loan = session.people.loans.first(where: { $0.id == loanID }) else { return }
                didLoad = true
                if let date = loan.dueDate { hasDue = true; due = date.startDate(in: .current) }
                if let bps = loan.interestBasisPoints { rate = SplitText.percent(Int64(bps)).replacingOccurrences(of: "%", with: "") }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let bps = SplitEditorView.basisPoints(rate)
        if session.perform("Couldn't save. Try again.", {
            try session.peopleClient.setDueDate(hasDue ? LocalDate(due, in: .current) : nil, bps > 0 ? Int(bps) : nil, loanID)
        }) {
            dismiss()
        }
    }
}

/// Settle up (SPL-08): a payment between you and one person, full or partial, from any account.
struct SettleUpSheet: View {
    @Bindable var session: AppSession
    let personID: UUID
    let groupID: UUID?
    /// My balance with them in base: negative means I pay.
    let suggested: Money
    @Environment(\.dismiss) private var dismiss
    @State private var iPay = true
    @State private var amount = ""
    @State private var accountID: UUID?
    @State private var date = Date()
    @State private var problem: String?
    @State private var didLoad = false

    private var name: String { session.people.person(personID)?.name ?? "them" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Who pays", selection: $iPay) {
                        Text("You pay \(name)").tag(true)
                        Text("\(name) pays you").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settle.direction")
                    HStack {
                        Text(session.ledger.base.symbol).font(.title.bold()).foregroundStyle(UZColor.label2)
                        TextField("0", text: $amount)
                            .font(.title.bold())
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                            .accessibilityIdentifier("settle.amount")
                    }
                }
                Section {
                    Picker(iPay ? "From" : "Into", selection: $accountID) {
                        ForEach(session.ledger.activeAccounts.filter { $0.currency == session.ledger.base }) { account in
                            Text(account.name).tag(UUID?.some(account.id))
                        }
                    }
                    .accessibilityIdentifier("settle.account")
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                } footer: {
                    Text(hint)
                }
                if let problem {
                    Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(UZColor.negative) }
                }
            }
            .navigationTitle("Settle up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold).accessibilityIdentifier("settle.save")
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                iPay = suggested.minorUnits <= 0
                if !suggested.isZero { amount = plainNumber(SplitText.magnitude(suggested)) }
                accountID = session.ledger.activeAccounts.first { $0.currency == session.ledger.base }?.id
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var hint: String {
        guard !suggested.isZero else { return "You're settled with \(name). A payment now starts a new balance." }
        let full = MoneyFormatter.string(SplitText.magnitude(suggested))
        return suggested.isNegative ? "You owe \(name) \(full). Not spending." : "\(name) owes you \(full). Not income."
    }

    private func save() {
        guard let accountID else { problem = "Choose an account."; return }
        let money: Money
        do {
            money = try AmountParser.parse(amount, currency: session.ledger.base)
        } catch {
            problem = ProblemText.message(error)
            return
        }
        guard money.minorUnits > 0 else { problem = "The amount must be more than zero."; return }
        if session.perform("Couldn't save. Nothing was changed. Try again.", {
            try session.peopleClient.settle(personID, groupID, money, iPay, accountID, date)
        }) {
            session.toasts.show("Settlement saved")
            dismiss()
        }
    }
}

/// Remind (LOAN-07, SPL-11): an editable message sent from the user's own phone; UZee never contacts anyone.
struct RemindSheet: View {
    let name: String
    let balance: Money
    var groupName: String?
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $message)
                        .frame(minHeight: 120)
                        .accessibilityIdentifier("remind.message")
                } header: {
                    Text("Message · edit before sending")
                } footer: {
                    Text("Sent from your own phone. UZee doesn't contact anyone for you.")
                }
                Section {
                    ShareLink(item: message) { Label("Send", systemImage: "paperplane.fill") }
                        .accessibilityIdentifier("remind.send")
                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = message }
                }
            }
            .navigationTitle("Remind \(name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                guard message.isEmpty else { return }
                let amount = MoneyFormatter.string(SplitText.magnitude(balance))
                let context = groupName.map { " for \($0)" } ?? ""
                message = balance.isNegative
                    ? "Hi \(name), I owe you \(amount)\(context). I'll send it soon."
                    : "Hi \(name), just a reminder about the \(amount)\(context). Could you send it when you can? Thanks!"
            }
        }
        .presentationDetents([.medium])
    }
}
