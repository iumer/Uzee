import Foundation

/// Checks the on-device model's reply against what the tools said, so a total it made up is never spoken (owner, 2026-10-16).
public enum ReplyNumbers {
    /// True when the reply has a number of three or more digits that none of the tool texts has.
    public static func unsupported(reply: String, sources: [String]) -> Bool {
        let known = Set(sources.flatMap { numbers(in: $0) })
        return numbers(in: reply).contains { $0.count >= 3 && !known.contains($0) }
    }

    /// Runs of digits with thousands commas dropped: "Rs 15,509" is "15509".
    static func numbers(in text: String) -> [String] {
        let chars = Array(text)
        var found: [String] = []
        var current = ""
        for (index, c) in chars.enumerated() {
            if c.isASCII, c.isNumber {
                current.append(c)
            } else if c == ",", !current.isEmpty, index + 1 < chars.count, chars[index + 1].isASCII, chars[index + 1].isNumber {
                continue
            } else if !current.isEmpty {
                found.append(current)
                current = ""
            }
        }
        if !current.isEmpty { found.append(current) }
        return found
    }
}
