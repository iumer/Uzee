import Foundation

/// A payment whose name or note reads like a loan or a repayment, so voice can ask whether it is really spending
/// (owner, 2026-10-16). It never changes a total.
public enum LoanWords {
    static let words = ["loan", "qarz", "qarza", "udhar", "udhaar", "repay", "repaid", "repayment", "returned"]
    /// Interest, markup or fees on a loan are real costs.
    static let costs = ["interest", "markup", "mark up", "fee", "fees", "charges", "insurance"]

    public static func looksLikeLoan(_ payee: String?, _ note: String?) -> Bool {
        let text = " " + VoiceRuleParser.normalise([payee, note].compactMap { $0 }.joined(separator: " ")) + " "
        guard words.contains(where: { text.contains(" " + $0 + " ") }) else { return false }
        return !costs.contains { text.contains(" " + $0 + " ") }
    }
}
