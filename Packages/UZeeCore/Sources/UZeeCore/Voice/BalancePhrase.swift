import Foundation

/// "Balance in my HBL account is 35,771, please update it": the real balance of one account, to set by a
/// balance adjustment like Reconcile (owner, 2026-10-14). The on-device model had turned it into an expense.
public enum BalancePhrase {
    public struct Request: Equatable, Sendable {
        /// The account as named, or nil when the sentence doesn't say ("the actual amount is 35,771, update it").
        public var account: String?
        public var amount: SpokenAmount
    }

    public static func request(_ sentence: String, vocabulary: VoiceVocabulary) -> Request? {
        // "rupees35771" → "rupees 35771"
        let spaced = sentence.replacingOccurrences(of: #"([A-Za-z])(\d)"#, with: "$1 $2", options: .regularExpression)
        let t = " " + VoiceRuleParser.normalise(spaced) + " "
        let talksBalance = [" balance ", " actual amount ", " real amount ", " amount in my ", " i have ", " there is ", " theres "]
            .contains { t.contains($0) }
        let asksChange = [" update ", " set ", " correct ", " fix ", " change ", " make it ", " should be ", " reconcile ", " actually ",
                          " actual ", " real "].contains { t.contains($0) }
        guard talksBalance, asksChange || t.contains(" is "),
              !VoiceRuleParser.isQuestion(t, original: sentence) || asksChange else { return nil }
        // "35771 not 25,000": the amount before "not" is the one meant.
        var amountText = spaced
        for marker in [" not ", " instead of ", " rather than "] {
            if let range = amountText.range(of: marker, options: .caseInsensitive) { amountText = String(amountText[..<range.lowerBound]) }
        }
        guard let amount = AmountPhrase.find(in: amountText) else { return nil }
        let account = VoiceRuleParser.findAccounts(t, vocabulary: vocabulary).first?.name
        return Request(account: account, amount: amount)
    }
}
