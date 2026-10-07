import Foundation
import UZeeCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Understands a request (VOX-03…08). Common sentences go through `VoiceRuleParser`, which works on every
/// device; Apple's on-device model (Foundation Models) is asked only when the rules don't understand,
/// and its answer is checked against the user's own names. Amounts are always read by `AmountPhrase`.
public enum VoiceUnderstanding {
    /// nil when Apple's on-device model can be used; otherwise why not, in plain words (VOX-08).
    public static func modelProblem() -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return "This device doesn't support Apple Intelligence, so UZee understands common sentences only."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Apple Intelligence is off, so UZee understands common sentences only. Turn it on in Settings › Apple Intelligence & Siri."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence is still getting ready, so UZee understands common sentences only for now."
            default:
                return "Apple Intelligence isn't available, so UZee understands common sentences only."
            }
        }
        #endif
        return "Apple Intelligence isn't available, so UZee understands common sentences only."
    }

    public static func understand(_ text: String, vocabulary: VoiceVocabulary, today: LocalDate) async -> VoiceCommand {
        let rules = VoiceRuleParser.parse(text, vocabulary: vocabulary, today: today)
        let understood = rules.action != .unknown && !(rules.action == .question && rules.question == nil)
        if understood || modelProblem() != nil { return rules }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), let fromModel = await ModelParser.parse(text, vocabulary: vocabulary, today: today) {
            return fromModel
        }
        #endif
        return rules
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedVoiceCommand {
    @Guide(description: "One of: expense, income, transfer, lend, borrow, repaidToMe, repaidByMe, question, unknown")
    var action: String
    @Guide(description: "The amount exactly as the user said it, such as 20k, 1.5 lakh, $20 or 2500. Empty if none.")
    var amount: String
    @Guide(description: "The other person's name or relationship (for loans, repayments or questions about a person). Empty if none.")
    var person: String
    @Guide(description: "The account the money came from, such as HBL, Meezan, Cash or Easypaisa. Empty if none.")
    var account: String
    @Guide(description: "For transfers only: the account the money went to. Empty otherwise.")
    var toAccount: String
    @Guide(description: "The spending or income category, such as groceries, fuel or salary. Empty if none.")
    var category: String
    @Guide(description: "The shop, company or payer. Empty if none.")
    var payee: String
    @Guide(description: "For questions only, one of: iOwe, owesMe, budgetLeft, spent, nextBill, subscriptions, balance, dueBeforeSalary, upcoming. Empty otherwise.")
    var question: String
    @Guide(description: "For spending questions: today, thisWeek, thisMonth or lastMonth. Empty otherwise.")
    var period: String
}

@available(iOS 26.0, macOS 26.0, *)
enum ModelParser {
    static let instructions = """
    You turn one sentence from the user of a personal finance app in Pakistan into a structured command. \
    Money is in Pakistani rupees unless the user says dollars. "Lend" means the user gave money that will be returned; \
    "borrow" means the user received money they must return; "repaidToMe" means someone returned money to the user; \
    "repaidByMe" means the user returned money. Questions ask about balances, bills, budgets, spending or what people owe. \
    Leave a field empty when the sentence doesn't say it. Never invent amounts or names.
    """

    static func parse(_ text: String, vocabulary: VoiceVocabulary, today: LocalDate) async -> VoiceCommand? {
        let session = LanguageModelSession(instructions: instructions)
        guard let generated = try? await session.respond(to: text, generating: GeneratedVoiceCommand.self).content else { return nil }
        guard let action = VoiceAction(rawValue: generated.action), action != .unknown else { return nil }
        let rules = VoiceRuleParser.parse(text, vocabulary: vocabulary, today: today)
        func said(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let person = VoiceRuleParser.resolve(said(generated.person), among: vocabulary.people) ?? said(generated.person).map(ReceiptParser.tidy)
        let account = VoiceRuleParser.resolve(said(generated.account), among: vocabulary.accounts)
        let category = VoiceRuleParser.resolve(said(generated.category), among: vocabulary.categories)
        var command = VoiceCommand(action: action,
                                   amount: AmountPhrase.find(in: text) ?? said(generated.amount).flatMap(AmountPhrase.find(in:)),
                                   person: person, account: account,
                                   toAccount: VoiceRuleParser.resolve(said(generated.toAccount), among: vocabulary.accounts),
                                   category: category, payee: said(generated.payee).map(ReceiptParser.tidy), date: rules.date)
        if action == .question {
            let period = VoicePeriod(rawValue: generated.period) ?? .thisMonth
            switch generated.question {
            case "iOwe": command.question = .iOwe(person: person)
            case "owesMe": command.question = .owesMe(person: person)
            case "budgetLeft": command.question = .budgetLeft
            case "spent": command.question = .spent(category: category, period: period)
            case "nextBill": command.question = .nextBill
            case "subscriptions": command.question = .subscriptions
            case "balance": command.question = .balance(account: account)
            case "dueBeforeSalary": command.question = .dueBeforeSalary
            case "upcoming": command.question = .upcoming
            default: return nil
            }
        }
        return command
    }
}
#endif
