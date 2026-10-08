import Foundation

/// What the UZee helper can do in the app while it talks with the user (VOX-01…08). The app supplies these;
/// the on-device model (UZeeSystem) calls them as tools and words the result for the user.
/// Each returns a short plain-text result for the model to read.
public struct AssistantActions: Sendable {
    /// Answers a question from the user's own data ("How much do I owe Ammi?").
    public var answer: @Sendable (VoiceQuestion) async -> String
    /// Shows a confirmation card for something to log; nothing is saved yet.
    public var prepare: @Sendable (VoiceCommand) async -> String
    /// Saves the card on screen.
    public var confirm: @Sendable () async -> String
    /// Throws the card on screen away.
    public var cancel: @Sendable () async -> String
    /// Finds transactions by payee, category, note or amount in a period.
    public var search: @Sendable (_ text: String, _ period: VoicePeriod?) async -> String
    /// Balances, this month's spending, budget left and the next bill.
    public var overview: @Sendable () async -> String
    /// Adds a reminder to the calendar ("Remind me to pay the plumber 5,000 on Friday at 5").
    public var remind: @Sendable (_ title: String, _ date: LocalDate, _ minuteOfDay: Int?, _ amount: Money?) async -> String

    public init(answer: @escaping @Sendable (VoiceQuestion) async -> String,
                prepare: @escaping @Sendable (VoiceCommand) async -> String,
                confirm: @escaping @Sendable () async -> String,
                cancel: @escaping @Sendable () async -> String,
                search: @escaping @Sendable (String, VoicePeriod?) async -> String,
                overview: @escaping @Sendable () async -> String,
                remind: @escaping @Sendable (String, LocalDate, Int?, Money?) async -> String = { _, _, _, _ in
                    "Reminders can't be added here."
                }) {
        self.answer = answer
        self.prepare = prepare
        self.confirm = confirm
        self.cancel = cancel
        self.search = search
        self.overview = overview
        self.remind = remind
    }
}

/// A conversation with the on-device model that remembers earlier turns.
public protocol AssistantChat: AnyObject, Sendable {
    /// UZee's reply, or nil when the model couldn't answer (the app then falls back to its rules).
    func reply(to text: String) async -> String?
}

/// Short answers that confirm or cancel the card on screen, spoken or typed ("yes, save it", "no").
public enum AssistantReply {
    public enum Intent: Equatable, Sendable { case confirm, cancel }

    static let confirmWords = ["yes", "yeah", "yep", "yup", "save", "save it", "confirm", "ok", "okay", "do it", "go ahead", "sure",
                               "correct", "right", "haan", "han", "ji", "theek hai", "done", "perfect", "sounds good"]
    static let cancelWords = ["no", "nope", "cancel", "don't", "do not", "stop", "never mind", "nevermind", "forget it",
                              "discard", "nahi", "nahin", "wrong"]

    /// Words that can sit around a yes or a no without changing it ("yes please", "no thanks").
    static let fillerWords = ["it", "that", "this", "please", "ji", "bhai", "uzee", "thanks", "thank you", "is", "that is",
                              "thats", "fine", "good", "all good", "its"]

    /// Only a plain yes or no counts; anything more is an edit: "no, make it 3,000" or "yes, from Meezan"
    /// go to the model (or the rules) instead.
    public static func intent(_ text: String) -> Intent? {
        let t = VoiceRuleParser.normalise(text)
        let words = t.split(separator: " ")
        guard !words.isEmpty, words.count <= 5 else { return nil }
        let padded = " " + t + " "
        var rest = padded
        for phrase in (confirmWords + cancelWords + fillerWords).sorted(by: { $0.count > $1.count }) {
            while rest.contains(" " + phrase + " ") { rest = rest.replacingOccurrences(of: " " + phrase + " ", with: " ") }
        }
        guard rest.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if cancelWords.contains(where: { padded.contains(" " + $0 + " ") }) { return .cancel }
        if confirmWords.contains(where: { padded.contains(" " + $0 + " ") }) { return .confirm }
        return nil
    }

    /// The sentence says yes somewhere ("yes, from Meezan"), so a card fixed in the same turn may be saved.
    public static func saysYes(_ text: String) -> Bool {
        let t = " " + VoiceRuleParser.normalise(text) + " "
        guard !cancelWords.contains(where: { t.contains(" " + $0 + " ") }) else { return false }
        return [" yes ", " save ", " confirm ", " haan ", " han ", " ok ", " okay ", " go ahead ", " yeah "].contains { t.contains($0) }
    }

    /// "Thanks, bye" ends a hands-free conversation.
    public static func isGoodbye(_ text: String) -> Bool {
        let t = " " + VoiceRuleParser.normalise(text) + " "
        guard t.split(separator: " ").count <= 5 else { return false }
        // "Paid 2,000 for petrol, thanks" is an entry, not a goodbye.
        guard AmountPhrase.find(in: t) == nil else { return false }
        if [" stop ", " stop it ", " ok stop ", " that will do "].contains(t) { return true }
        return [" bye ", " goodbye ", " that all ", " thats all ", " that is all ", " nothing else ", " stop listening ",
                " thank you ", " thanks ", " shukriya "].contains { t.contains($0) }
    }
}
