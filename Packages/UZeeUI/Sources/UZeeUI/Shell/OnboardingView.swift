import SwiftUI
import UZeeCore

/// First launch (SCR-01): welcome, the banks and wallets you use with today's balances, and when your salary
/// comes. Shown once, while there are no accounts; "Try sample data" skips it.
struct OnboardingView: View {
    @Bindable var session: AppSession
    let finish: () -> Void

    enum Step: Int { case welcome, accounts, salary }

    struct Pick: Identifiable, Equatable {
        let name: String
        let kind: AccountKind
        var currency: Currency
        var balance = ""
        var id: String { name }
    }

    @State private var step: Step = .welcome
    @State private var picks: [Pick] = []
    @State private var salaryDay = 0
    @State private var problem: String?

    static let defaultsKey = "uzee.onboarded"

    /// True on a real first launch: never set up, no accounts, not sample data, not a UI test.
    static func isNeeded(_ session: AppSession) -> Bool {
        guard !ProcessInfo.processInfo.arguments.contains("-uzee-in-memory"), session.isDatabaseReady,
              !UserDefaults.standard.bool(forKey: defaultsKey) else { return false }
        return session.ledger.accounts.isEmpty && !session.isSampleMode
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome: welcome
                case .accounts: accounts
                case .salary: salary
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: UZSpacing.s)], spacing: UZSpacing.s) {
                    ForEach(AccountFormSheet.presets, id: \.name) { preset in
                        let chosen = picks.contains { $0.name == preset.name }
                        Button {
                            if chosen { picks.removeAll { $0.name == preset.name } } else {
                                picks.append(Pick(name: preset.name, kind: preset.kind,
                                                  currency: preset.kind == .multiCurrency ? .usd : .pkr))
                            }
                        } label: {
                            Text(preset.name).font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity).padding(.vertical, UZSpacing.m)
                                .background(chosen ? UZColor.tint.opacity(0.2) : UZColor.fill, in: .rect(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(chosen ? UZColor.tint : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                        .accessibilityIdentifier("onboarding.pick.\(preset.name)")
                    }
                }
                .padding(.vertical, UZSpacing.xs)
            } header: {
                Text("Where do you keep money?")
            } footer: {
                Text("Pick all that apply. You can add others later in Accounts.")
            }
            if !picks.isEmpty {
                Section {
                    ForEach($picks) { $pick in
                        HStack {
                            Text(pick.name)
                            Spacer()
                            Picker("", selection: $pick.currency) {
                                Text("Rs").tag(Currency.pkr)
                                Text("$").tag(Currency.usd)
                            }
                            .labelsHidden().fixedSize()
                            TextField("0", text: $pick.balance)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
                                .frame(maxWidth: 120)
                                .accessibilityIdentifier("onboarding.balance.\(pick.name)")
                        }
                    }
                } header: {
                    Text("Balance today")
                } footer: {
                    Text("What each one holds right now. Leave 0 if you're not sure; you can fix it later.")
                }
            }
            if let problem {
                Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(UZColor.negative) }
            }
        }
        .navigationTitle("Your accounts")
        .safeAreaInset(edge: .bottom) {
            Button { step = .salary } label: {
                Text(picks.isEmpty ? "Skip" : "Next").font(.headline).frame(maxWidth: .infinity).padding(.vertical, UZSpacing.s)
            }
            .buttonStyle(.glassProminent)
            .padding(.horizontal, UZSpacing.xxl).padding(.bottom, UZSpacing.m)
            .accessibilityIdentifier("onboarding.next")
        }
    }

    // MARK: Salary

    private var salary: some View {
        Form {
            Section {
                Picker("Salary comes on", selection: $salaryDay) {
                    Text("Not fixed").tag(0)
                    ForEach(1...28, id: \.self) { Text("Day \($0)").tag($0) }
                }
                .accessibilityIdentifier("onboarding.salaryDay")
            } header: {
                Text("When does your salary come?")
            } footer: {
                Text(salaryDay == 0 ? "Budgets run by calendar month."
                                    : "Budgets run from day \(salaryDay) to the day before the next salary.")
            }
            if let problem {
                Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(UZColor.negative) }
            }
        }
        .navigationTitle("Salary")
        .safeAreaInset(edge: .bottom) {
            Button { save() } label: {
                Text("Start using UZee").font(.headline).frame(maxWidth: .infinity).padding(.vertical, UZSpacing.s)
            }
            .buttonStyle(.glassProminent)
            .padding(.horizontal, UZSpacing.xxl).padding(.bottom, UZSpacing.m)
            .accessibilityIdentifier("onboarding.done")
        }
    }

    private func save() {
        let today = session.today
        var opening: [(Pick, Money)] = []
        for pick in picks {
            let text = pick.balance.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { opening.append((pick, .zero(pick.currency))); continue }
            guard let money = try? AmountParser.parse(text, currency: pick.currency) else {
                problem = "Check the balance for \(pick.name)."
                step = .accounts
                return
            }
            opening.append((pick, money))
        }
        do {
            for (pick, money) in opening where !session.ledger.accounts.contains(where: { $0.name == pick.name }) {
                _ = try session.client.createAccount(.init(name: pick.name, kind: pick.kind, currency: pick.currency,
                                                           openingBalance: money, openingDate: today, includeInTotals: true))
            }
            if salaryDay > 0 {
                let warn = (try? session.budgets.settings().warnPercent) ?? 80
                try session.budgets.setSettings(.salaryCycle(startDay: salaryDay), warn)
            }
        } catch {
            // Accounts saved before the failure are kept; a retry skips them.
            session.reload()
            problem = "Couldn't save. Try again."
            return
        }
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
