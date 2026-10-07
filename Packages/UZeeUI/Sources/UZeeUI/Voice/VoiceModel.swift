import Foundation
import Observation
import UZeeCore

/// The editable confirmation card (VOX-07): nothing is saved until the user taps Save.
struct VoiceCard: Equatable {
    var action: VoiceAction
    var amountText: String
    var personID: UUID?
    /// Said but not in People yet (VOX-08); created when the card is saved.
    var newPersonName: String?
    var accountID: UUID?
    var toAccountID: UUID?
    var categoryID: UUID?
    var payee: String
    var date: Date
    var problem: String?

    static let actions: [VoiceAction] = [.expense, .income, .transfer, .lend, .borrow, .repaidToMe, .repaidByMe]

    static func title(_ action: VoiceAction) -> String {
        switch action {
        case .expense: "Expense"
        case .income: "Income"
        case .transfer: "Transfer"
        case .lend: "Lent"
        case .borrow: "Borrowed"
        case .repaidToMe: "Paid back to you"
        case .repaidByMe: "You paid back"
        case .question, .unknown: "Request"
        }
    }
}

/// Ask UZee conversation (SCR-03, J5): listen or type, understand, ask follow-ups, answer or show a card.
@MainActor
@Observable
final class VoiceModel {
    struct Line: Identifiable, Equatable {
        enum Speaker { case me, uzee }
        let id = UUID()
        let speaker: Speaker
        let text: String
    }

    let session: AppSession
    var lines: [Line] = []
    var draft = ""
    var isListening = false
    var isThinking = false
    var card: VoiceCard?
    /// Waiting for an answer to a follow-up question (VOX-05).
    private var pending: VoiceCommand?
    private var need: VoiceDialog.Need?

    init(session: AppSession) {
        self.session = session
    }

    var modelProblem: String? { session.smart.voiceModelProblem() }

    var vocabulary: VoiceVocabulary { session.voiceVocabulary }

    // MARK: Listening

    func toggleListening() {
        if isListening { stopListening() } else { Task { await startListening() } }
    }

    private func startListening() async {
        guard await session.smart.requestSpeechAccess() else {
            say("I can't hear you yet. Allow the microphone and speech recognition for UZee in Settings, or type instead.")
            return
        }
        draft = ""
        do {
            try session.smart.startListening { text, isFinal in
                Task { @MainActor in self.heard(text, isFinal: isFinal) }
            }
            isListening = true
        } catch {
            say("Voice isn't available right now. Use the keyboard instead.")
        }
    }

    func stopListening() {
        session.smart.stopListening()
    }

    func cancelListening() {
        session.smart.cancelListening()
        isListening = false
    }

    private func heard(_ text: String, isFinal: Bool) {
        guard isListening else { return }
        if !text.isEmpty { draft = text }
        if isFinal {
            isListening = false
            let sentence = draft
            draft = ""
            if !sentence.trimmingCharacters(in: .whitespaces).isEmpty { submit(sentence) }
        }
    }

    // MARK: Conversation

    func submit(_ text: String) {
        let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return }
        draft = ""
        lines.append(Line(speaker: .me, text: sentence))
        if let pending, let need {
            self.pending = nil
            self.need = nil
            handle(VoiceDialog.apply(sentence, to: pending, need: need, vocabulary: vocabulary))
            return
        }
        isThinking = true
        let smart = session.smart
        let vocabulary = vocabulary
        let today = session.today
        Task {
            let command = await smart.understand(sentence, vocabulary, today)
            isThinking = false
            handle(command)
        }
    }

    private func handle(_ command: VoiceCommand) {
        switch command.action {
        case .unknown:
            say("Sorry, I didn't get that. Try \"How much do I owe Ammi?\" or \"Spent 2,500 on groceries\".")
        case .question:
            guard let question = command.question else {
                say("Sorry, I can't answer that yet.")
                return
            }
            say(VoiceAnswerer(session: session).answer(question))
        default:
            if let need = VoiceDialog.need(command) {
                pending = command
                self.need = need
                say(VoiceDialog.prompt(need, for: command))
                return
            }
            showCard(for: command)
        }
    }

    private func say(_ text: String) {
        lines.append(Line(speaker: .uzee, text: text))
    }

    // MARK: Card

    private func showCard(for command: VoiceCommand) {
        let ledger = session.ledger
        let accounts = ledger.activeAccounts
        func account(_ name: String?) -> UUID? {
            guard let name else { return nil }
            return accounts.first { NameKey.make($0.name) == NameKey.make(name) }?.id
        }
        var accountID = account(command.account)
        if accountID == nil {
            // "$20" goes to a dollar account; otherwise the last used account.
            if let currency = command.amount?.currency, currency != ledger.base {
                accountID = accounts.first { $0.currency == currency }?.id
            }
            if accountID == nil, let last = try? session.client.lastUsedAccountID(), accounts.contains(where: { $0.id == last }) {
                accountID = last
            }
            accountID = accountID ?? accounts.first?.id
        }
        let currency = ledger.account(accountID)?.currency ?? ledger.base
        let amountText = command.amount.flatMap { try? Money.fromMajor($0.value, currency) }.map(plainNumber) ?? ""

        var personID: UUID?
        var newPerson: String?
        if let name = command.person {
            if let person = VoiceAnswerer(session: session).person(named: name) { personID = person.id } else { newPerson = name }
        }

        var categoryID: UUID?
        let type: CategoryType = command.action == .income ? .income : .expense
        let pickable = ledger.categories.filter { $0.type == type && !$0.isHidden }
        if let name = command.category {
            categoryID = pickable.first { NameKey.make($0.name) == NameKey.make(name) }?.id
        }
        if categoryID == nil, let payee = command.payee {
            let remembered = (try? session.activity.rememberedCategories()) ?? [:]
            categoryID = CategorySuggester.suggest(payee: payee, remembered: remembered, categories: pickable)
        }
        let date = command.date.map { day -> Date in
            let time = Calendar.current.dateComponents([.hour, .minute], from: Date())
            return Calendar.current.date(byAdding: time, to: day.startDate(in: .current)) ?? day.startDate(in: .current)
        } ?? Date()

        card = VoiceCard(action: command.action, amountText: amountText, personID: personID, newPersonName: newPerson,
                         accountID: accountID, toAccountID: account(command.toAccount), categoryID: categoryID,
                         payee: command.payee ?? "", date: date)
        var intro = "Here's the \(VoiceCard.title(command.action).lowercased()). Change anything, then save."
        if let newPerson { intro = "\(newPerson) is new. I'll add them to People when you save. " + intro }
        else if let personID, command.action == .lend || command.action == .borrow {
            let net = session.balances.net(of: personID)
            let name = session.people.person(personID)?.name ?? ""
            if !net.isZero {
                let amount = MoneyFormatter.string(Money(minorUnits: net.minorUnits.magnitudeClamped, currency: net.currency))
                intro = (net.isNegative ? "You already owe \(name) \(amount). " : "\(name) already owes you \(amount). ") + intro
            }
        }
        say(intro)
    }

    func cancelCard() {
        card = nil
        say("Cancelled. Nothing was saved.")
    }

    /// Saves the card (VOX-07). Returns a short "Saved · …" line.
    func save() {
        guard var card else { return }
        card.problem = nil
        let ledger = session.ledger
        let currency = ledger.account(card.accountID)?.currency ?? ledger.base
        let amount: Money
        do {
            amount = try AmountParser.parse(card.amountText, currency: currency)
        } catch {
            card.problem = ProblemText.message(error)
            self.card = card
            return
        }
        let result: String?
        switch card.action {
        case .expense, .income, .transfer:
            result = saveTransaction(&card, amount: amount)
        case .lend, .borrow, .repaidToMe, .repaidByMe:
            result = saveLoan(&card, amount: amount)
        case .question, .unknown:
            result = nil
        }
        if let result {
            self.card = nil
            say(result)
        } else {
            // The app-wide error alert can't show over this sheet, so a save failure goes on the card.
            if card.problem == nil, let message = session.errorMessage {
                card.problem = message
                session.errorMessage = nil
            }
            self.card = card
        }
    }

    private func saveTransaction(_ card: inout VoiceCard, amount: Money) -> String? {
        let ledger = session.ledger
        let kind: TransactionKind = card.action == .income ? .income : card.action == .transfer ? .transfer : .expense
        let payee = card.payee.trimmingCharacters(in: .whitespaces)
        let draft = TransactionDraft(kind: kind, status: .posted, amount: amount, accountID: card.accountID,
                                     toAccountID: kind == .transfer ? card.toAccountID : nil,
                                     categoryID: kind == .transfer ? nil : card.categoryID,
                                     payeeName: kind == .transfer || payee.isEmpty ? nil : payee,
                                     occurredAt: card.date, timeZone: .current, source: .voice)
        let built: MoneyTransaction
        do {
            built = try TransactionValidator.build(draft, accounts: ledger.accounts, base: ledger.base)
        } catch {
            card.problem = error == .missingReceivedAmount
                ? "These accounts use different currencies. Use the Add screen to enter the amount that arrived."
                : ProblemText.message(error)
            return nil
        }
        guard session.save(built, isNew: true) else { return nil }
        let what = payee.isEmpty ? (ledger.categoryPath(card.categoryID) ?? VoiceCard.title(card.action)) : payee
        return "Saved · \(what) \(MoneyFormatter.string(amount))."
    }

    private func saveLoan(_ card: inout VoiceCard, amount: Money) -> String? {
        var personID = card.personID
        if personID == nil, let name = card.newPersonName?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            do {
                personID = try session.peopleClient.createPerson(name, nil).id
            } catch {
                card.problem = "Couldn't add \(name) to People. Try a different name."
                return nil
            }
        }
        guard let personID else {
            card.problem = "Choose a person."
            return nil
        }
        card.personID = personID
        card.newPersonName = nil
        session.reload()
        let name = session.people.person(personID)?.name ?? "them"
        switch card.action {
        case .lend, .borrow:
            let direction: LoanDirection = card.action == .lend ? .lent : .borrowed
            let accountID = card.accountID
            let date = card.date
            guard session.perform("Couldn't save. Nothing was changed. Try again.", {
                try session.peopleClient.recordLoan(direction, personID, amount, accountID, date, nil, nil)
            }) else { return nil }
            session.toasts.show(direction == .lent ? "Lent \(MoneyFormatter.string(amount)) to \(name)" : "Borrowed \(MoneyFormatter.string(amount)) from \(name)")
            return direction == .lent ? "Saved · Lent \(MoneyFormatter.string(amount)) to \(name)." : "Saved · Borrowed \(MoneyFormatter.string(amount)) from \(name)."
        default:
            let direction: LoanDirection = card.action == .repaidToMe ? .lent : .borrowed
            let open = session.people.loans
                .filter { $0.personID == personID && $0.direction == direction && $0.writtenOffAt == nil && LoanCalculator.outstanding($0).minorUnits > 0 }
                .sorted { $0.startDate < $1.startDate }
            guard let loan = open.first else {
                card.problem = direction == .lent ? "\(name) has no open loan from you. Record it in People instead."
                    : "You have no open loan from \(name). Record it in People instead."
                return nil
            }
            guard let accountID = card.accountID else {
                card.problem = "Choose an account."
                return nil
            }
            let date = card.date
            guard session.perform("Couldn't save. Check the amount isn't more than what's left on the loan.", {
                try session.peopleClient.recordRepayment(loan.id, amount, accountID, date)
            }) else { return nil }
            session.toasts.show("Repayment saved")
            return "Saved · \(direction == .lent ? "\(name) paid you back" : "You paid \(name) back") \(MoneyFormatter.string(amount))."
        }
    }
}

extension AppSession {
    /// The user's own names for voice matching (VOX-06).
    var voiceVocabulary: VoiceVocabulary {
        VoiceVocabulary(people: people.others.map(\.name),
                        accounts: ledger.activeAccounts.map(\.name),
                        categories: ledger.categories.filter { !$0.isHidden }.map(\.name))
    }

    /// Siri "Ask UZee" (VOX-01): one spoken answer, the same numbers as the screens. Anything that would
    /// save something is sent to the app instead, because UZee always shows a card first (VOX-07).
    public func answer(_ text: String) async -> String {
        reload()
        let command = await smart.understand(text, voiceVocabulary, today)
        switch command.action {
        case .question:
            guard let question = command.question else { return "Sorry, I can't answer that yet." }
            return VoiceAnswerer(session: self).answer(question)
        case .unknown:
            return "Sorry, I didn't get that. Try asking how much you owe someone, your next bill or your budget."
        default:
            return "To add something, say \"Add to UZee\". I'll open UZee so you can check it before it's saved."
        }
    }
}
