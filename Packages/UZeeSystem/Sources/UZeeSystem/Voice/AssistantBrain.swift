import Foundation
import UZeeCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The UZee helper's conversation (VOX-01…08): Apple's on-device model talks with the user and uses the app
/// through tools (answer, look up, prepare a card, save or cancel it). Nothing leaves the device.
public enum AssistantBrain {
    /// A new conversation, or nil when Apple Intelligence isn't available (the app then uses its rules).
    public static func start(actions: AssistantActions, vocabulary: VoiceVocabulary, today: LocalDate) -> (any AssistantChat)? {
        guard VoiceUnderstanding.modelProblem() == nil else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return ModelChat(actions: actions, vocabulary: vocabulary, today: today)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
final class ModelChat: AssistantChat, @unchecked Sendable {
    private let actions: AssistantActions
    private let vocabulary: VoiceVocabulary
    private let today: LocalDate
    private var session: LanguageModelSession
    private let lock = NSLock()
    /// What the user said so far, so the tools can drop details the model made up.
    private let heard = Heard()

    init(actions: AssistantActions, vocabulary: VoiceVocabulary, today: LocalDate) {
        self.actions = actions
        self.vocabulary = vocabulary
        self.today = today
        session = Self.makeSession(actions: actions, vocabulary: vocabulary, today: today, heard: heard)
    }

    static func instructions(vocabulary: VoiceVocabulary, today: LocalDate) -> String {
        """
        You are UZee, a friendly money helper inside a personal finance app in Pakistan. You talk with the user by \
        voice, so answer in one or two short spoken sentences, without lists, markdown or emoji. Amounts are in \
        Pakistani rupees unless the user says another currency. Write rupees as Rs (for example Rs 5,000), never ₹ or INR. Today is \(today.year)-\(today.month)-\(today.day).

        Use the tools for anything about the user's money; never guess numbers. To log something (spent, received, \
        transferred, lent, borrowed, paid back, or a debt such as "I owe my mom 250000" = borrow and "Ali owes me 5000" = \
        lend, with justADebt true) call prepareEntry. A cheque deposited, submitted or cashed into an account is \
        income into that account, never a transfer from that account to itself. Fill in only what the user said: \
        leave the account, person and date empty when they didn't say them, and never pick an account for them. It shows a card; then tell the user what is on it \
        and ask them to confirm. Only call confirmEntry after the user clearly agrees, and cancelEntry if they say no. \
        If they want a change, call prepareEntry again with the corrected details. If prepareEntry says something is \
        missing, ask the user for it. For a question about one number (an account's balance, budget left, spending, \
        bills, subscriptions, who owes whom) call answerQuestion with the matching kind; use overview only for "how am \
        I doing", and findTransactions to look up a shop or word. Only say numbers a tool gave you, and never log \
        anything when the user asks a question. A line in brackets at the start describes the card already on screen. To be reminded \
        of something later ("remind me to pay the plumber on Friday"), call addReminder.

        The user's people: \(vocabulary.people.prefix(30).joined(separator: ", ")).
        Accounts: \(vocabulary.accounts.prefix(15).joined(separator: ", ")).
        Categories: \(vocabulary.categories.prefix(40).joined(separator: ", ")).
        """
    }

    static func makeSession(actions: AssistantActions, vocabulary: VoiceVocabulary, today: LocalDate, heard: Heard) -> LanguageModelSession {
        let tools: [any Tool] = [
            PrepareEntryTool(actions: actions, vocabulary: vocabulary, today: today, heard: heard),
            ConfirmEntryTool(actions: actions),
            CancelEntryTool(actions: actions),
            AnswerQuestionTool(actions: actions, vocabulary: vocabulary),
            FindTransactionsTool(actions: actions),
            OverviewTool(actions: actions),
            AddReminderTool(actions: actions, today: today)
        ]
        return LanguageModelSession(tools: tools, instructions: instructions(vocabulary: vocabulary, today: today))
    }

    func reply(to text: String) async -> String? {
        heard.add(text)
        let current = lock.withLock { session }
        do {
            return try await current.respond(to: text).content
        } catch let error as LanguageModelSession.GenerationError where error.isTooLong {
            // A long conversation can outgrow the model's memory: start a fresh one and try once more.
            let fresh = Self.makeSession(actions: actions, vocabulary: vocabulary, today: today, heard: heard)
            lock.withLock { session = fresh }
            return try? await fresh.respond(to: text).content
        } catch {
            // Anything else (guardrails, busy, unsupported language): the app's own rules answer instead,
            // and the conversation so far is kept.
            return nil
        }
    }
}

/// Everything the user said in one conversation.
final class Heard: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func add(_ line: String) { lock.withLock { lines.append(line) } }
    var all: String { lock.withLock { lines.joined(separator: " . ") } }
    var last: String { lock.withLock { lines.last ?? "" } }
}

@available(iOS 26.0, macOS 26.0, *)
struct PrepareEntryTool: Tool {
    let actions: AssistantActions
    let vocabulary: VoiceVocabulary
    let today: LocalDate
    let heard: Heard
    let name = "prepareEntry"
    let description = "Shows a card to log an expense, income, transfer, loan or repayment. Nothing is saved until confirmEntry."

    @Generable
    struct Arguments {
        @Guide(description: "One of: expense, income, transfer, lend, borrow, repaidToMe, repaidByMe")
        var action: String
        @Guide(description: "The amount as the user said it, such as 20k, 1.5 lakh, $20 or 2500. Empty if not said yet.")
        var amount: String
        @Guide(description: "The other person for loans and repayments. Empty if none.")
        var person: String
        @Guide(description: "The account the money came from or went into, such as HBL, Meezan or Cash. Empty if not said.")
        var account: String
        @Guide(description: "For transfers only: the account the money went to. Empty otherwise.")
        var toAccount: String
        @Guide(description: "The category, such as groceries, fuel or salary. Empty if not said.")
        var category: String
        @Guide(description: "The shop, company or payer. Empty if none.")
        var payee: String
        @Guide(description: "When it happened, as the user said it, such as today, yesterday or 5 October. Empty for today.")
        var when: String
        @Guide(description: "True when the user only records a debt and no money moves now: 'I owe my mom 250000' (borrow) or 'Ali owes me 5000' (lend).")
        var justADebt: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        let generated = ModelParser.Fields(action: arguments.action, amount: arguments.amount, person: arguments.person,
                                              account: arguments.account, toAccount: arguments.toAccount,
                                              category: arguments.category, payee: arguments.payee, question: "", period: "")
        guard var command = ModelParser.command(from: generated, said: arguments.amount, vocabulary: vocabulary, today: today) else {
            return "That isn't something UZee can log. Ask the user what they want to record."
        }
        command.date = VoiceRuleParser.parse(arguments.when, vocabulary: vocabulary, today: today).date
        if arguments.justADebt, command.action == .borrow || command.action == .lend { command.noMoneyMoved = true }
        command = VoiceRuleParser.keepingOnlySaid(command, heard: heard.all, vocabulary: vocabulary)
        command = VoiceRuleParser.refiningCategory(command, sentence: heard.last, vocabulary: vocabulary, today: today)
        return await actions.prepare(command)
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct ConfirmEntryTool: Tool {
    let actions: AssistantActions
    let name = "confirmEntry"
    let description = "Saves the card on screen. Call only after the user agrees."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String { await actions.confirm() }
}

@available(iOS 26.0, macOS 26.0, *)
struct CancelEntryTool: Tool {
    let actions: AssistantActions
    let name = "cancelEntry"
    let description = "Throws away the card on screen without saving."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String { await actions.cancel() }
}

@available(iOS 26.0, macOS 26.0, *)
struct AnswerQuestionTool: Tool {
    let actions: AssistantActions
    let vocabulary: VoiceVocabulary
    let name = "answerQuestion"
    let description = "Answers a question about the user's money from their own data."

    @Generable
    struct Arguments {
        @Guide(description: "One of: iOwe, owesMe, budgetLeft, spent, nextBill, subscriptions, balance, dueBeforeSalary, upcoming, afford (can the user afford a purchase)")
        var question: String
        @Guide(description: "The person, for iOwe or owesMe. Empty for everyone.")
        var person: String
        @Guide(description: "The category, for spent. Empty for all spending.")
        var category: String
        @Guide(description: "The account, for balance. Empty for all accounts.")
        var account: String
        @Guide(description: "For spent: today, thisWeek, thisMonth or lastMonth.")
        var period: String
        @Guide(description: "For afford: the price as the user said it, such as 30,000 or 1.5 lakh. Empty otherwise.")
        var amount: String
    }

    func call(arguments: Arguments) async throws -> String {
        func value(_ text: String) -> String? { text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : text }
        let person = VoiceRuleParser.resolve(value(arguments.person), among: vocabulary.people) ?? value(arguments.person)
        let category = VoiceRuleParser.resolve(value(arguments.category), among: vocabulary.categories)
        let account = VoiceRuleParser.resolve(value(arguments.account), among: vocabulary.accounts)
        guard let question = ModelParser.question(arguments.question, person: person, category: category, account: account,
                                                  period: VoicePeriod(rawValue: arguments.period) ?? .thisMonth,
                                                  amount: AmountPhrase.find(in: arguments.amount)) else {
            return "UZee can't answer that kind of question yet."
        }
        return await actions.answer(question)
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct FindTransactionsTool: Tool {
    let actions: AssistantActions
    let name = "findTransactions"
    let description = "Finds the user's transactions by shop, person, category, note or amount, and totals them."

    @Generable
    struct Arguments {
        @Guide(description: "What to look for, such as foodpanda, fuel, Usama or 2500.")
        var text: String
        @Guide(description: "today, thisWeek, thisMonth or lastMonth. Empty for any time.")
        var period: String
    }

    func call(arguments: Arguments) async throws -> String {
        await actions.search(arguments.text, VoicePeriod(rawValue: arguments.period))
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct AddReminderTool: Tool {
    let actions: AssistantActions
    let today: LocalDate
    let name = "addReminder"
    let description = "Adds a reminder to the user's UZee calendar for a future day, optionally at a time and with an amount."

    @Generable
    struct Arguments {
        @Guide(description: "What to remind about, short, such as Pay the plumber or Car tuning.")
        var title: String
        @Guide(description: "The day as the user said it, such as tomorrow, Friday, in 3 days or 20 October.")
        var when: String
        @Guide(description: "The time as the user said it, such as 5 pm or in the evening. Empty if not said.")
        var time: String
        @Guide(description: "An amount if the user said one, such as 5,000 or 2k. Empty otherwise.")
        var amount: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let date = ReminderPhrase.date(arguments.when, today: today) else {
            return "The day isn't clear. Ask the user which day."
        }
        let amount = AmountPhrase.find(in: arguments.amount).flatMap { try? Money.fromMajor($0.value, $0.currency ?? .pkr) }
        return await actions.remind(arguments.title, date, ReminderPhrase.minuteOfDay(arguments.time + " " + arguments.when), amount)
    }
}

@available(iOS 26.0, macOS 26.0, *)
extension LanguageModelSession.GenerationError {
    var isTooLong: Bool {
        if case .exceededContextWindowSize = self { return true }
        return false
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct OverviewTool: Tool {
    let actions: AssistantActions
    let name = "overview"
    let description = "The user's total balance, this month's spending, budget left and next bill."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String { await actions.overview() }
}
#endif
