import SwiftUI
import UZeeCore

/// First launch (SCR-01): welcome, the accounts you keep money in (by kind, as many of each as you like, any
/// currency), then how you earn. Only a salary asks for a payday. Shown once, while there are no accounts;
/// "Try sample data" skips it.
struct OnboardingView: View {
    @Bindable var session: AppSession
    let finish: () -> Void

    enum Step: Int { case welcome, accounts, income }

    /// Account groups on the setup screen. No country's banks are listed; you type your own names.
    struct Group: Identifiable {
        let kind: AccountKind
        let title: String
        let symbol: String
        let add: String
        let placeholder: String
        var id: AccountKind { kind }
    }

    static let groups: [Group] = [
        Group(kind: .cash, title: "Cash", symbol: "banknote", add: "Add cash", placeholder: "Cash"),
        Group(kind: .bank, title: "Bank accounts", symbol: "building.columns", add: "Add bank account", placeholder: "Bank name"),
        Group(kind: .wallet, title: "Wallets", symbol: "iphone.gen3", add: "Add wallet", placeholder: "Wallet name"),
        Group(kind: .multiCurrency, title: "Online & multi-currency", symbol: "globe", add: "Add online account",
              placeholder: "e.g. Wise, Payoneer, PayPal"),
    ]

    struct Pick: Identifiable, Equatable {
        let id = UUID()
        let kind: AccountKind
        var name = ""
        var currency: Currency
        var balance = ""
    }

    /// How you earn (OWN-020). Only a salary has a fixed payday by default.
    enum IncomeType: String, CaseIterable, Identifiable {
        case salaried, business, freelancer, other
        var id: String { rawValue }

        var title: String {
            switch self {
            case .salaried: "Salary"
            case .business: "Business"
            case .freelancer: "Freelance"
            case .other: "Something else"
            }
        }

        var detail: String {
            switch self {
            case .salaried: "A job that pays on a set day"
            case .business: "Your own shop or company"
            case .freelancer: "Clients pay you per job"
            case .other: "Pension, family, savings, student"
            }
        }

        var symbol: String {
            switch self {
            case .salaried: "briefcase"
            case .business: "storefront"
            case .freelancer: "laptopcomputer"
            case .other: "ellipsis.circle"
            }
        }

        /// The question for a regular payment when there's no salary.
        var regularQuestion: String {
            switch self {
            case .salaried: ""
            case .business: "I pay myself a set amount each month"
            case .freelancer: "A client pays me on a set day each month"
            case .other: "Money comes on a set day each month"
            }
        }

        /// Name of the recurring income UZee adds.
        var incomeName: String {
            switch self {
            case .salaried: "Salary"
            case .business: "Owner's pay"
            case .freelancer: "Retainer"
            case .other: "Monthly income"
            }
        }
    }

    @State private var step: Step = .welcome
    @State private var picks: [Pick] = []
    @State private var incomeType: IncomeType?
    @State private var hasRegular = false
    @State private var payDay = 0
    @State private var payAmount = ""
    @State private var payCurrency: Currency = .pkr
    @State private var problem: String?
    /// Accounts already saved, by pick, so a retry after a failed save doesn't add them twice.
    @State private var created: [UUID: String] = [:]

    static let defaultsKey = "uzee.onboarded"
    static let incomeTypeKey = "uzee.incomeType"

    /// True on a real first launch: never set up, no accounts, not sample data, not a UI test.
    static func isNeeded(_ session: AppSession) -> Bool {
        guard !ProcessInfo.processInfo.arguments.contains("-uzee-in-memory"), session.isDatabaseReady,
              !UserDefaults.standard.bool(forKey: defaultsKey) else { return false }
        return session.ledger.accounts.isEmpty && !session.isSampleMode
    }

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                switch step {
                case .welcome: welcome
                case .accounts: accounts
                case .income: income
                }
            }
            .animation(.smooth, value: step)
            .toolbar {
                if step != .welcome {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear { payCurrency = session.ledger.base }
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(spacing: UZSpacing.xl) {
            Spacer()
            HelperOrb(mood: .listening, size: 110)
            VStack(spacing: UZSpacing.s) {
                Text("Welcome to UZee").font(.largeTitle.bold())
                Text("Track spending, bills, loans and splits. Everything stays on this iPhone.")
                    .font(.body).foregroundStyle(UZColor.label2).multilineTextAlignment(.center)
            }
            .padding(.horizontal, UZSpacing.xxl)
            Spacer()
            VStack(spacing: UZSpacing.m) {
                Button { step = .accounts } label: {
                    Text("Set up").font(.headline).frame(maxWidth: .infinity).padding(.vertical, UZSpacing.s)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("onboarding.start")
                Button("Try with sample data") {
                    session.turnOnSampleData()
                    done()
                }
                .accessibilityIdentifier("onboarding.sample")
            }
            .padding(.horizontal, UZSpacing.xxl)
            .padding(.bottom, UZSpacing.xl)
        }
    }

    // MARK: Accounts

    private var accounts: some View {
        Form {
            Section {
                Text("Add each place you keep money and what it holds today. Add as many of each as you like; you can change them later.")
                    .font(.subheadline).foregroundStyle(UZColor.label2)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: UZSpacing.xs, bottom: 0, trailing: UZSpacing.xs))
            }
            ForEach(Self.groups) { group in
                Section {
                    ForEach(picks.filter { $0.kind == group.kind }) { pick in
                        accountRow(binding(for: pick.id), group: group)
                    }
                    .onDelete { offsets in remove(offsets, kind: group.kind) }
                    Button {
                        withAnimation(.snappy) { add(group) }
                    } label: {
                        Label(group.add, systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("onboarding.add.\(group.kind.rawValue)")
                } header: {
                    Label(group.title, systemImage: group.symbol)
                }
            }
            if let problem {
                Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(UZColor.negative) }
            }
        }
        .navigationTitle("Where's your money?")
        .safeAreaInset(edge: .bottom) {
            Button { problem = nil; step = .income } label: {
                Text(picks.isEmpty ? "Skip" : "Next").font(.headline).frame(maxWidth: .infinity).padding(.vertical, UZSpacing.s)
            }
            .buttonStyle(.glassProminent)
            .padding(.horizontal, UZSpacing.xxl).padding(.bottom, UZSpacing.m)
            .accessibilityIdentifier("onboarding.next")
        }
    }

    private func accountRow(_ pick: Binding<Pick>, group: Group) -> some View {
        VStack(alignment: .leading, spacing: UZSpacing.s) {
            TextField(group.placeholder, text: pick.name)
                .font(.body.weight(.medium))
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("onboarding.name.\(group.kind.rawValue)")
            HStack {
                Menu {
                    Picker("Currency", selection: pick.currency) {
                        ForEach(Currency.known, id: \.code) { Text("\($0.code) · \($0.symbol)").tag($0) }
                    }
                } label: {
                    Text(pick.wrappedValue.currency.code).font(.subheadline.weight(.semibold))
                        .padding(.horizontal, UZSpacing.m).padding(.vertical, UZSpacing.xs)
                        .background(UZColor.fill, in: .capsule)
                }
                .accessibilityIdentifier("onboarding.currency.\(group.kind.rawValue)")
                Spacer()
                Text("Balance").font(.subheadline).foregroundStyle(UZColor.label2)
                TextField("0", text: pick.balance)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
                    .frame(maxWidth: 130)
                    .accessibilityIdentifier("onboarding.balance.\(group.kind.rawValue)")
            }
        }
        .padding(.vertical, UZSpacing.xxs)
    }

    /// A binding by id, so deleting a row never leaves another row pointing at a stale index.
    private func binding(for id: UUID) -> Binding<Pick> {
        Binding(get: { picks.first { $0.id == id } ?? Pick(kind: .cash, currency: session.ledger.base) },
                set: { new in if let index = picks.firstIndex(where: { $0.id == id }) { picks[index] = new } })
    }

    private func add(_ group: Group) {
        let count = picks.filter { $0.kind == group.kind }.count
        // Cash gets its name straight away; banks and wallets are typed in.
        let name = group.kind == .cash ? (count == 0 ? "Cash" : "Cash \(count + 1)") : ""
        let base = session.ledger.base
        let currency = group.kind == .multiCurrency && base == .pkr ? Currency.usd : base
        picks.append(Pick(kind: group.kind, name: name, currency: currency))
    }

    private func remove(_ offsets: IndexSet, kind: AccountKind) {
        let ids = picks.filter { $0.kind == kind }.enumerated().filter { offsets.contains($0.offset) }.map(\.element.id)
        picks.removeAll { ids.contains($0.id) }
    }

    /// The saved name: what was typed, or "Bank 2"-style when left empty, never clashing with another account.
    private func finalNames() -> [UUID: String] {
        var used = Set(session.ledger.accounts.map { $0.name.lowercased() })
        var result = created
        for group in Self.groups {
            let fallback = group.kind == .cash ? "Cash" : group.kind == .bank ? "Bank" : group.kind == .wallet ? "Wallet" : "Online account"
            for pick in picks where pick.kind == group.kind && created[pick.id] == nil {
                let typed = pick.name.trimmingCharacters(in: .whitespaces)
                let stem = typed.isEmpty ? fallback : typed
                var name = stem
                var n = 2
                while used.contains(name.lowercased()) { name = "\(stem) \(n)"; n += 1 }
                used.insert(name.lowercased())
                result[pick.id] = name
            }
        }
        return result
    }

    // MARK: Income

    private var income: some View {
        Form {
            Section {
                ForEach(IncomeType.allCases) { type in
                    Button {
                        withAnimation(.snappy) {
                            if incomeType != type { hasRegular = false }
                            incomeType = type
                        }
                    } label: {
                        HStack(spacing: UZSpacing.l) {
                            Image(systemName: type.symbol).font(.title3).foregroundStyle(UZColor.tint).frame(width: 30)
                            VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                                Text(type.title).font(.body.weight(.medium)).foregroundStyle(UZColor.label)
                                Text(type.detail).font(.footnote).foregroundStyle(UZColor.label2)
                            }
                            Spacer()
                            if incomeType == type {
                                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(UZColor.tint)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(incomeType == type ? .isSelected : [])
                    .accessibilityIdentifier("onboarding.income.\(type.rawValue)")
                }
            } header: {
                Text("How do you earn?")
            }
            if let incomeType {
                if incomeType == .salaried {
                    paydaySection(title: "When does your salary come?")
                } else {
                    Section {
                        Toggle(incomeType.regularQuestion, isOn: $hasRegular.animation(.snappy))
                            .accessibilityIdentifier("onboarding.regular")
                    } footer: {
                        Text(incomeType == .business
                             ? "Business income changes month to month, so budgets run by calendar month."
                             : incomeType == .freelancer
                             ? "Freelance pay comes when clients pay, so budgets run by calendar month."
                             : "Budgets run by calendar month.")
                    }
                    if hasRegular { paydaySection(title: "Which day?") }
                }
                if incomeType == .salaried || hasRegular {
                    Section {
                        HStack {
                            Picker("", selection: $payCurrency) {
                                ForEach(Currency.known, id: \.code) { Text($0.code).tag($0) }
                            }
                            .labelsHidden().fixedSize()
                            TextField("Amount", text: $payAmount)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
                                .accessibilityIdentifier("onboarding.payAmount")
                        }
                    } header: {
                        Text(incomeType == .salaried ? "Monthly salary (optional)" : "Amount (optional)")
                    } footer: {
                        Text("With an amount and a day, Home shows what's due before it comes, and the calendar reminds you to mark it received.")
                    }
                }
            }
            if let problem {
                Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(UZColor.negative) }
            }
        }
        .navigationTitle("Your income")
        .safeAreaInset(edge: .bottom) {
            Button { save() } label: {
                Text("Start using UZee").font(.headline).frame(maxWidth: .infinity).padding(.vertical, UZSpacing.s)
            }
            .buttonStyle(.glassProminent)
            .padding(.horizontal, UZSpacing.xxl).padding(.bottom, UZSpacing.m)
            .accessibilityIdentifier("onboarding.done")
        }
    }

    private func paydaySection(title: String) -> some View {
        Section {
            DayGrid(selection: $payDay, allowsNotFixed: incomeType == .salaried, identifier: "onboarding.payDay")
                .padding(.vertical, UZSpacing.xs)
        } header: {
            Text(title)
        } footer: {
            if incomeType == .salaried {
                Text(payDay == 0 ? "Budgets run by calendar month."
                                 : "Budgets run from the \(Self.ordinal(payDay)) to the day before the next salary. Short months use their last day.")
            } else if payDay > 28 {
                Text("Short months use their last day.")
            }
        }
    }

    static func ordinal(_ day: Int) -> String {
        let suffix = (11...13).contains(day % 100) ? "th" : [1: "st", 2: "nd", 3: "rd"][day % 10] ?? "th"
        return "\(day)\(suffix)"
    }

    private func save() {
        problem = nil
        let today = session.today
        let names = finalNames()
        var opening: [(Pick, String, Money)] = []
        for pick in picks {
            let name = names[pick.id] ?? pick.name
            let text = pick.balance.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { opening.append((pick, name, .zero(pick.currency))); continue }
            guard let money = try? AmountParser.parse(text, currency: pick.currency) else {
                problem = "Check the balance for \(name)."
                step = .accounts
                return
            }
            opening.append((pick, name, money))
        }
        let regular = incomeType == .salaried || hasRegular
        var pay: Money?
        let payText = payAmount.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        if regular, !payText.isEmpty {
            guard let money = try? AmountParser.parse(payText, currency: payCurrency), money.minorUnits > 0 else {
                problem = "Check the amount."
                return
            }
            pay = money
        }
        if hasRegular, incomeType != .salaried, payDay == 0 {
            problem = "Pick the day it comes, or turn the switch off."
            return
        }
        do {
            var firstAccount: UUID?
            for (pick, name, money) in opening where created[pick.id] == nil {
                let account = try session.client.createAccount(.init(name: name, kind: pick.kind, currency: pick.currency,
                                                                     openingBalance: money, openingDate: today, includeInTotals: true))
                created[pick.id] = name
                if pick.currency == payCurrency, pick.kind != .cash, firstAccount == nil { firstAccount = account.id }
            }
            if incomeType == .salaried, payDay > 0 {
                let warn = (try? session.budgets.settings().warnPercent) ?? 80
                try session.budgets.setSettings(.salaryCycle(startDay: payDay), warn)
            }
            if let incomeType, regular, payDay > 0, let pay {
                let first = RecurrenceRule.nextMonthly(day: payDay, onOrAfter: today)
                let income = session.ledger.categories.filter { $0.type == .income && !$0.isHidden }
                let category = (incomeType == .salaried ? income.first(where: { $0.systemKey == "income.salary" }) : nil) ?? income.first
                let item = RecurringItem(name: incomeType.incomeName, type: incomeType == .salaried ? .salary : .income, amount: pay,
                                         accountID: firstAccount, categoryID: category?.id,
                                         rule: RecurrenceRule(anchor: first), trackedFrom: first, startedOn: first, colorHex: "#34C759")
                try session.recurringClient.save(item, nil)
            }
        } catch {
            // Accounts saved before the failure are kept; a retry skips them.
            session.reload()
            problem = "Couldn't save. Try again."
            return
        }
        if let incomeType { UserDefaults.standard.set(incomeType.rawValue, forKey: Self.incomeTypeKey) }
        session.reload()
        done()
        // Bill reminders need permission; ask now that setup is done, once.
        Task { _ = await session.calendar.requestNotifications(); session.rescheduleReminders() }
    }

    private func done() {
        UserDefaults.standard.set(true, forKey: Self.defaultsKey)
        finish()
    }
}
