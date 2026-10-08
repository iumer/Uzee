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
        guard let systemKey = systemKey(inText: [payee]) else { return nil }
        return categories.first { $0.systemKey == systemKey && !$0.isHidden }?.id
    }

    /// The default category a shop name or receipt text points to, from well-known merchants and item words.
    public static func systemKey(inText lines: [String]) -> String? {
        let text = " " + lines.joined(separator: " ").lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ").joined(separator: " ") + " "
        return known.first { entry in entry.words.contains { text.contains(" " + $0 + " ") } }?.key
    }

    /// Checked in order; the first match wins, so specific shops come before general words.
    static let known: [(words: [String], key: String)] = [
        (["foodpanda", "food panda", "cheetay"], "food.food_delivery"),
        (["careem", "uber", "indrive", "bykea", "yango"], "transport.ride_hailing"),
        (["shell", "pso", "attock", "total parco", "go petrol", "hascol", "petrol", "fuel", "diesel", "hi octane", "litre", "ltr"],
         "transport.fuel"),
        (["parking", "toll", "motorway", "m tag"], "transport.parking_tolls"),
        (["motors", "autos", "auto parts", "spare parts", "tyre", "tyres", "tire", "tires", "car wash", "wax", "coating",
          "polish", "detailing", "engine oil", "oil change", "mobil oil", "lubricant", "mechanic", "workshop", "battery",
          "brake", "alignment", "service station"], "transport.car_maintenance"),
        (["imtiaz", "carrefour", "naheed", "metro", "chase up", "al fatah", "hyperstar", "springs", "grocery", "groceries",
          "super market", "supermarket", "kiryana", "karyana", "bakery", "milk", "vegetables", "fruit"],
         "food.groceries"),
        (["kababjees", "kfc", "mcdonalds", "mcdonald s", "pizza", "burger", "hardees", "subway", "restaurant", "cafe",
          "dhaba", "bbq", "biryani", "karahi", "grill", "dine in", "dine", "waiter", "table no"], "food.dining_out"),
        (["chai", "tea", "coffee", "starbucks", "gloria jeans", "tim hortons", "snacks", "juice"], "food.tea_snacks"),
        (["pharmacy", "pharma", "medical store", "chemist", "clinix", "dvago", "servaid", "medicine", "tablet", "tablets",
          "syrup", "capsule"], "health.medicine"),
        (["laboratory", "lab test", "chughtai", "excel lab", "diagnostic"], "health.lab_tests"),
        (["hospital", "clinic", "doctor", "consultation"], "health.doctor"),
        (["jazz", "zong", "telenor", "ufone", "easyload", "mobile load"], "utilities.mobile"),
        (["electric", "electricity", "lesco", "iesco", "kelectric", "k electric", "mepco", "fesco", "gepco", "pesco"],
         "utilities.electricity"),
        (["sui gas", "sngpl", "ssgc"], "utilities.gas"),
        (["ptcl", "nayatel", "stormfiber", "storm fiber", "transworld", "wateen", "internet"], "utilities.internet"),
        (["netflix", "spotify", "youtube", "disney", "prime video", "tamasha"], "subscriptions.streaming"),
        (["icloud", "google one", "dropbox"], "subscriptions.cloud_storage"),
        (["openai", "chatgpt", "anthropic", "claude", "cursor", "github", "adobe", "figma", "notion"],
         "subscriptions.software_ai_tools"),
        (["outfitters", "khaadi", "sapphire", "gul ahmed", "bonanza", "breakout", "zara", "clothing",
          "shirt", "jeans", "shoes", "kurta"], "personal.clothing"),
        (["salon", "barber", "saloon", "grooming", "spa", "parlour"], "personal.grooming"),
        (["book", "books", "liberty books", "readings"], "education.books"),
        (["udemy", "coursera", "course", "tuition", "academy"], "education.courses"),
        (["cinema", "cinepax", "nueplex", "movie"], "entertainment.outings"),
        (["steam", "playstation", "xbox"], "entertainment.games"),
        (["hotel", "airline", "pia", "airblue", "serene air", "booking com", "airbnb", "flight"], "entertainment.travel"),
        (["furniture", "interwood", "habitt"], "housing.furniture"),
        (["hardware", "plumber", "electrician", "paint"], "housing.maintenance"),
        (["edhi", "shaukat khanum", "donation", "charity"], "charity.donations"),
        // General shop words last, so "medical store" stays medicine.
        (["mart", "store", "general store"], "food.groceries")
    ]
}
