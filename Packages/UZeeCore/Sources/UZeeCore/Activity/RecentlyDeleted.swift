import Foundation

/// Recently Deleted rules (PRD DATA-05): deleted items stay restorable for 30 days, then are purged.
public enum RecentlyDeleted {
    public static let retentionDays = 30

    /// Purge when 30 full days have passed since deletion. Day 29 is still restorable (DATA-013).
    public static func isExpired(deletedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(deletedAt) >= Double(retentionDays) * 86_400
    }

    /// The cut-off: anything deleted at or before this instant is purged.
    public static func cutoff(now: Date) -> Date {
        now.addingTimeInterval(-Double(retentionDays) * 86_400)
    }

    /// Whole days left before purge, for "Deleted · 12 days left".
    public static func daysLeft(deletedAt: Date, now: Date) -> Int {
        let remaining = Double(retentionDays) * 86_400 - now.timeIntervalSince(deletedAt)
        return max(0, Int((remaining / 86_400).rounded(.up)))
    }
}

/// A receipt photo or PDF attached to a transaction (ATT-001…003). Not named `Attachment`, which
/// clashes with Swift Testing.
public struct ReceiptFile: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case photo, pdf
    }

    public var id: UUID
    public var transactionID: UUID
    public var kind: Kind
    /// File name inside the protected attachments folder.
    public var fileName: String
    public var byteCount: Int64
    public var createdAt: Date
    public var isSample: Bool

    public init(id: UUID = UUID(), transactionID: UUID, kind: Kind, fileName: String, byteCount: Int64,
                createdAt: Date = Date(), isSample: Bool = false) {
        self.id = id
        self.transactionID = transactionID
        self.kind = kind
        self.fileName = fileName
        self.byteCount = byteCount
        self.createdAt = createdAt
        self.isSample = isSample
    }

    /// Largest file accepted, so one receipt can't fill the phone.
    public static let maxBytes: Int64 = 20 * 1_024 * 1_024
}

/// Suggests a category from the payee (CAT-007, AI-01 rule-based part). A payee's own last category wins;
/// otherwise a short list of well-known Pakistani merchants maps to a default category key.
public enum CategorySuggester {
    public static func suggest(payee: String?, remembered: [String: UUID], categories: [SpendCategory]) -> UUID? {
        guard let payee, !payee.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let key = NameKey.make(payee)
        if let id = remembered[key], categories.contains(where: { $0.id == id && !$0.isHidden }) { return id }
        let words = Set(key.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        guard let systemKey = known.first(where: { !words.isDisjoint(with: $0.words) })?.key else { return nil }
        return categories.first { $0.systemKey == systemKey && !$0.isHidden }?.id
    }

    static let known: [(words: Set<String>, key: String)] = [
        (["careem", "uber", "indrive", "bykea", "yango"], "transport.ride_hailing"),
        (["shell", "pso", "attock", "petrol", "fuel"], "transport.fuel"),
        (["foodpanda"], "food.food_delivery"),
        (["imtiaz", "carrefour", "naheed", "metro", "chase", "grocery", "groceries"], "food.groceries"),
        (["kababjees", "kfc", "mcdonalds", "restaurant", "cafe"], "food.dining_out"),
        (["jazz", "zong", "telenor", "ufone"], "utilities.mobile"),
        (["electric", "electricity", "lesco", "iesco"], "utilities.electricity"),
        (["ptcl", "nayatel", "stormfiber"], "utilities.internet"),
        (["netflix", "spotify", "youtube"], "subscriptions.streaming"),
        (["icloud"], "subscriptions.cloud_storage")
    ]
}
