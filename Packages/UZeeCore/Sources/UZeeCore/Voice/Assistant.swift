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

    public init(answer: @escaping @Sendable (VoiceQuestion) async -> String,
                prepare: @escaping @Sendable (VoiceCommand) async -> String,
                confirm: @escaping @Sendable () async -> String,
                cancel: @escaping @Sendable () async -> String,
                search: @escaping @Sendable (String, VoicePeriod?) async -> String,
                overview: @escaping @Sendable () async -> String) {
        self.answer = answer
        self.prepare = prepare
        self.confirm = confirm
        self.cancel = cancel
        self.search = search
        self.overview = overview
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

    /// Only short replies count, so "no, make it 3,000" is an edit, not a cancel.
    public static func intent(_ text: String) -> Intent? {
        let t = VoiceRuleParser.normalise(text)
        let words = t.split(separator: " ")
        guard !words.isEmpty, words.count <= 4 else { return nil }
        let padded = " " + t + " "
        if cancelWords.contains(where: { padded.contains(" " + $0 + " ") }) { return .cancel }
        if confirmWords.contains(where: { padded.contains(" " + $0 + " ") }) { return .confirm }
        return nil
    }

    /// "Thanks, bye" ends a hands-free conversation.
    public static func isGoodbye(_ text: String) -> Bool {
        let t = " " + VoiceRuleParser.normalise(text) + " "
        guard t.split(separator: " ").count <= 5 else { return false }
        return [" bye ", " goodbye ", " that all ", " thats all ", " that is all ", " nothing else ", " stop listening ",
                " thank you ", " thanks ", " shukriya "].contains { t.contains($0) }
    }
}
