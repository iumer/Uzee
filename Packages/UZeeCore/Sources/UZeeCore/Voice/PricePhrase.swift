import Foundation

/// "Today the actual subscription price of ChatGPT was 5,000": a dollar bill paid from a rupee account comes out a
/// little different each time (rate, taxes), so the user says the real amount and UZee corrects the latest charge and
/// the bill's amount (owner, 2026-10-15). The name is matched by the app against its bills and payees.
public enum PricePhrase {
    public struct Request: Equatable, Sendable {
        public var amount: SpokenAmount
        /// The sentence, lowercased and tidied, for matching a bill or payee name in it.
        public var text: String
    }

    public static func request(_ sentence: String) -> Request? {
        let spaced = sentence.replacingOccurrences(of: #"([A-Za-z])(\d)"#, with: "$1 $2", options: .regularExpression)
        let t = " " + VoiceRuleParser.normalise(spaced) + " "
        let correcting = [" actual ", " actually ", " real ", " correct ", " charged ", " was charged ", " deducted ", " cut "]
            .contains { t.contains($0) }
        let aboutPrice = [" price ", " charge ", " charges ", " amount ", " cost ", " subscription ", " fee ", " bill ", " charged ", " deducted "]
            .contains { t.contains($0) }
        guard correcting, aboutPrice, !t.contains(" balance ") else { return nil }
        // "5000 not 4998": the first amount is the real one.
        var amountText = spaced
        for marker in [" not ", " instead of ", " rather than ", " but ", " while ", " whereas "] {
            if let range = amountText.range(of: marker, options: .caseInsensitive) { amountText = String(amountText[..<range.lowerBound]) }
        }
        guard let amount = AmountPhrase.find(in: amountText) else { return nil }
        return Request(amount: amount, text: t)
    }
}
