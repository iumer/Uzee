import Foundation

/// UZee is for Pakistan: iOS dictation and the on-device model sometimes write Indian rupees ("₹40,000",
/// "INR"). Shown and spoken text always uses Rs instead (owner, 2026-10-12).
public enum RupeeText {
    public static func pakistani(_ text: String) -> String {
        guard text.contains("\u{20B9}") || text.range(of: "inr", options: .caseInsensitive) != nil
                || text.range(of: "indian rupee", options: .caseInsensitive) != nil else { return text }
        var result = text
        // "PKR ₹40,000" / "Rs ₹40,000": the sign is extra.
        result = result.replacingOccurrences(of: #"\b(PKR|Rs\.?)\s*₹\s*"#, with: "$1 ", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"₹\s*"#, with: "Rs ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\bINR\b"#, with: "PKR", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"\bIndian rupee"#, with: "rupee", options: [.regularExpression, .caseInsensitive])
        return result
    }
}
