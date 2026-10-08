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

/// The UZee helper (SCR-03, J5): a spoken conversation like Siri. It listens, works out when you've finished,
/// answers aloud and listens again. Apple's on-device model holds the conversation and uses the app through
/// tools (answer, look up, prepare a card, save it); without it, UZee's own rules understand common sentences.
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
    var isSpeaking = false
    /// Listening again after each reply, until the user says bye, stops it or goes quiet.
    var handsFree = false
    /// Replies are shown but not spoken.
    var muted = false
    var card: VoiceCard?
    private var silence: Task<Void, Never>?
    private var chat: (any AssistantChat)?
    private var triedChat = false
    /// Waiting for an answer to a follow-up question (VOX-05).
    private var pending: VoiceCommand?
    private var need: VoiceDialog.Need?
    /// Counts the user's sentences, so the model can't show a card and save it in the same turn.
    private var turn = 0
    private var cardTurn = 0
    private var lastSentence = ""

    init(session: AppSession) {
        self.session = session
    }

    var modelProblem: String? { session.smart.voiceModelProblem() }

    var vocabulary: VoiceVocabulary { session.voiceVocabulary }

    var usesModel: Bool { modelProblem == nil }

    // MARK: Listening

    /// Opening the helper starts listening straight away when the microphone is already allowed.
    func begin() {
        guard lines.isEmpty, card == nil, session.smart.canListen() else { return }
        handsFree = true
        Task { await startListening() }
    }

    /// The big button: stop talking, stop listening, or start a hands-free conversation.
    func toggleListening() {
        if isSpeaking {
            session.smart.stopSpeaking()
            return
        }
        if isListening {
            handsFree = false
            stopListening()
        } else {
            handsFree = true
            Task { await startListening() }
        }
    }

    private func startListening() async {
        guard !isListening else { return }
        guard await session.smart.requestSpeechAccess() else {
            handsFree = false
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
            handsFree = false
            say("Voice isn't available right now. Use the keyboard instead.")
        }
    }

    func stopListening() {
        silence?.cancel()
        session.smart.stopListening()
    }

    /// Closing the helper: stop listening and speaking, end the conversation.
    func cancelListening() {
        silence?.cancel()
        handsFree = false
        session.smart.cancelListening()
        session.smart.stopSpeaking()
        isListening = false
        isSpeaking = false
    }

    private func heard(_ text: String, isFinal: Bool) {
        guard isListening else { return }
        if !text.isEmpty { draft = text }
        if isFinal {
            silence?.cancel()
            isListening = false
            let sentence = draft
            draft = ""
            if sentence.trimmingCharacters(in: .whitespaces).isEmpty {
                // Nothing said: end the hands-free loop quietly.
                handsFree = false
            } else {
                submit(sentence)
            }
            return
        }
        // Finished speaking = a short pause after some words (or a longer one before any).
        silence?.cancel()
        let wait: Duration = draft.isEmpty ? .seconds(6) : .milliseconds(1_300)
        silence = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self, self.isListening else { return }
            self.session.smart.stopListening()
        }
    }

    // MARK: Conversation

    func submit(_ text: String) {
        let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // One reply at a time: the on-device model can't take a second request mid-answer.
        guard !sentence.isEmpty, !isThinking else { return }
        draft = ""
        turn += 1
        lastSentence = sentence
        lines.append(Line(speaker: .me, text: sentence))
        // "Yes" or "no" to the card on screen, or "cancel" to a follow-up question, spoken or typed.
        if card != nil || pending != nil, let intent = AssistantReply.intent(sentence) {
            let hadCard = card != nil
            pending = nil
            need = nil
            if intent == .confirm, hadCard { save() }
            else if hadCard { cancelCard() }
            else if intent == .cancel { say("OK, dropped it. Nothing was saved.") }
            else { say("Sorry, I still need that detail. Or say cancel.") }
            return
        }
        if AssistantReply.isGoodbye(sentence) {
            pending = nil
            need = nil
            say("Anytime. Bye for now!")
            handsFree = false
            return
        }
        if usesModel, pending == nil {
            converse(sentence)
            return
        }
        if let pending, let need {
            self.pending = nil
            self.need = nil
            handle(VoiceDialog.apply(sentence, to: pending, need: need, vocabulary: vocabulary))
            return
        }
        understandWithRules(sentence)
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
        speakThenListen(text)
    }

    /// Speaks the reply in a hands-free conversation, then listens for the next sentence.
    private func speakThenListen(_ text: String) {
        guard handsFree else { return }
        guard !muted else {
            Task { if handsFree { await startListening() } }
            return
        }
        isSpeaking = true
        session.smart.speak(text) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isSpeaking = false
                if self.handsFree { await self.startListening() }
            }
        }
    }

    /// One turn with the on-device model; falls back to the rules if it can't answer.
    private func converse(_ sentence: String) {
        if !triedChat {
            triedChat = true
            chat = session.smart.startAssistant(assistantActions, vocabulary, session.today)
        }
        guard let chat else {
            understandWithRules(sentence)
            return
        }
        isThinking = true
        Task {
            let reply = await chat.reply(to: sentence)
            isThinking = false
            if let reply, !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                say(reply)
            } else {
                understandWithRules(sentence)
            }
        }
    }

    private func understandWithRules(_ sentence: String) {
        if let answer = quickAnswer(sentence) {
            say(answer)
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

    /// Overviews and searches the rules don't cover: "How am I doing?", "Find Careem", "What did I spend on Foodpanda this month?".
    private func quickAnswer(_ sentence: String) -> String? {
        let answerer = VoiceAnswerer(session: session)
        if let request = ReminderPhrase.request(sentence, today: session.today, currency: session.ledger.base) {
            return addReminder(request)
        }
        if sentence.lowercased().hasPrefix("remind me") { return "Which day should I remind you? Say it with the day, like tomorrow or Friday." }
        var t = sentence.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if ["how am i doing", "overview", "summary", "how's my month", "how is my month", "how are my finances"].contains(where: t.contains) {
            return answerer.overview()
        }
        var period: VoicePeriod?
        for (words, value) in [("this month", VoicePeriod.thisMonth), ("last month", .lastMonth), ("this week", .thisWeek), ("today", .today)]
        where t.hasSuffix(" " + words) {
            period = value
            t = String(t.dropLast(words.count + 1))
        }
        var term: String?
        for lead in ["search for ", "search ", "find ", "look up ", "show me "] where t.hasPrefix(lead) {
            term = String(t.dropFirst(lead.count))
            break
        }
        if term == nil {
            for marker in ["spend on ", "spent on ", "paid to ", "pay to "] {
                if let range = t.range(of: marker) { term = String(t[range.upperBound...]); break }
            }
            // A category ("groceries") is answered by the rules, with only my shares counted.
            if let found = term, vocabulary.categories.contains(where: { NameKey.make($0) == NameKey.make(found) }) { return nil }
        }
        guard let term = term?.trimmingCharacters(in: .whitespaces), !term.isEmpty else { return nil }
        return answerer.search(term, period: period)
    }

    /// The app, as tools for the model. Each returns a short result the model words for the user.
    private var assistantActions: AssistantActions {
        AssistantActions(
            answer: { [weak self] question in
                guard let self else { return "" }
                return await self.answerForModel(question)
            },
            prepare: { [weak self] command in
                guard let self else { return "" }
                return await self.prepareForModel(command)
            },
            confirm: { [weak self] in
                guard let self else { return "" }
                return await self.confirmForModel()
            },
            cancel: { [weak self] in
                guard let self else { return "" }
                return await self.cancelForModel()
            },
            search: { [weak self] text, period in
                guard let self else { return "" }
                return await self.searchForModel(text, period: period)
            },
            overview: { [weak self] in
                guard let self else { return "" }
                return await self.overviewForModel()
            },
            remind: { [weak self] title, date, minute, amount in
                guard let self else { return "" }
                return await self.remindForModel(title, date: date, minute: minute, amount: amount)
            })
    }

    private func answerForModel(_ question: VoiceQuestion) -> String {
        VoiceAnswerer(session: session).answer(question)
    }

    private func searchForModel(_ text: String, period: VoicePeriod?) -> String {
        VoiceAnswerer(session: session).search(text, period: period)
    }

    private func remindForModel(_ title: String, date: LocalDate, minute: Int?, amount: Money?) -> String {
        addReminder(ReminderPhrase.Request(title: title, date: date, minuteOfDay: minute, amount: amount))
    }

    /// Saves a reminder said out loud (VOX-04) and says when it is.
    private func addReminder(_ request: ReminderPhrase.Request) -> String {
        let event = CalendarEvent(title: request.title, date: request.date, minuteOfDay: request.minuteOfDay, amount: request.amount)
        guard session.saveEvent(event) else { return "Couldn't add that reminder." }
        var when = DateText.short(request.date)
        if let minute = request.minuteOfDay { when += " at " + String(format: "%d:%02d", minute / 60, minute % 60) }
        return "Added \(request.title) to your calendar for \(when). I'll remind you."
    }

    private func overviewForModel() -> String {
        VoiceAnswerer(session: session).overview()
    }

    private func cancelForModel() -> String {
        guard card != nil else { return "There was no card on screen." }
        card = nil
        return "Cancelled. Nothing was saved."
    }

    private func prepareForModel(_ command: VoiceCommand) -> String {
        if let need = VoiceDialog.need(command) {
            return "Not shown yet. Missing information: " + VoiceDialog.prompt(need, for: command) + " Ask the user."
        }
        showCard(for: command, announce: false)
        guard let card else { return "Couldn't show the card." }
        if let problem = card.problem { return "The card is on screen but needs fixing: \(problem) Card: \(cardSummary(card)). Tell the user." }
        return "The card is on screen: \(cardSummary(card)). Ask the user to say yes to save or tell you what to change."
    }

    private func confirmForModel() -> String {
        guard card != nil else { return "There is no card on screen to save." }
        // Saving needs the user's yes, after they've seen the card.
        guard cardTurn < turn || AssistantReply.saysYes(lastSentence) else {
            return "Not saved yet: the user hasn't confirmed. Show the card and ask them to say yes."
        }
        let saved = commit()
        if let saved { return saved }
        return "Not saved: \(card?.problem ?? "something is missing"). Tell the user."
    }

    /// "Lent Rs 20,000 to Usama from HBL, today".
    private func cardSummary(_ card: VoiceCard) -> String {
        let ledger = session.ledger
        var parts = [VoiceCard.title(card.action) + " " + (card.amountText.isEmpty ? "(no amount)" : card.amountText)]
        if let name = card.personID.flatMap({ session.people.person($0)?.name }) ?? card.newPersonName { parts.append("person " + name) }
        if let account = ledger.account(card.accountID)?.name { parts.append("account " + account) }
        if let to = ledger.account(card.toAccountID)?.name { parts.append("to " + to) }
        if let category = ledger.categoryPath(card.categoryID) { parts.append("category " + category) }
        if !card.payee.isEmpty { parts.append("payee " + card.payee) }
        parts.append("date " + DateText.short(LocalDate(card.date, in: .current)))
        return parts.joined(separator: ", ")
    }

    // MARK: Card

    private func showCard(for command: VoiceCommand, announce: Bool = true) {
        let ledger = session.ledger
        let accounts = ledger.activeAccounts
        func account(_ name: String?) -> UUID? {
            guard let name else { return nil }
            return accounts.first { NameKey.make($0.name) == NameKey.make(name) }?.id
        }
        var accountID = account(command.account)
        var problem: String?
        if let named = command.account, accountID == nil {
            // An account that isn't in UZee ("JazzCash") must be picked, not swapped for another one quietly.
            problem = "There's no account called \(named). Pick one."
        } else if accountID == nil {
            // "$20" goes to a dollar account; otherwise the last used account.
            if let currency = command.amount?.currency, currency != ledger.base {
                accountID = accounts.first { $0.currency == currency }?.id
            }
            if accountID == nil, let last = try? session.client.lastUsedAccountID(), accounts.contains(where: { $0.id == last }) {
                accountID = last
            }
            accountID = accountID ?? accounts.first?.id
        }
        // "$20" never lands in a rupee account as Rs 20.
        if let said = command.amount?.currency, let chosen = ledger.account(accountID), chosen.currency != said {
            accountID = nil
            problem = "That's \(said.code). Pick a \(said.code) account."
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
                         payee: command.payee ?? "", date: date, problem: problem)
        cardTurn = turn
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
        if let problem { intro = problem + " " + intro }
        if announce { say(intro) }
    }

    func cancelCard() {
        card = nil
        say("Cancelled. Nothing was saved.")
    }

    /// Saves the card (VOX-07) and says "Saved · …"; a problem stays on the card.
    func save() {
        if let result = commit() {
            say(result)
        } else if let problem = card?.problem {
            speakThenListen(problem)
        }
    }

    /// Saves the card. Returns "Saved · …", or nil with the reason on the card.
    private func commit() -> String? {
        guard var card else { return nil }
        card.problem = nil
        let ledger = session.ledger
        let currency = ledger.account(card.accountID)?.currency ?? ledger.base
        let amount: Money
        do {
            amount = try AmountParser.parse(card.amountText, currency: currency)
        } catch {
            card.problem = ProblemText.message(error)
            self.card = card
            return nil
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
            return result
        }
        // The app-wide error alert can't show over this sheet, so a save failure goes on the card.
        if card.problem == nil, let message = session.errorMessage {
            card.problem = message
            session.errorMessage = nil
        }
        self.card = card
        return nil
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
