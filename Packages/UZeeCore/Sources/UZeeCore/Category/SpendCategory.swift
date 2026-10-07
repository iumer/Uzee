import Foundation

/// Which tree a category belongs to (DATA_MODEL §3.8 `kind`).
public enum CategoryType: String, CaseIterable, Sendable, Codable {
    case expense, income, system
}

/// A category row. `group` is the top-level `CategoryKind` that gives colour and symbol (AUD-16).
public struct SpendCategory: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var type: CategoryType
    public var parentID: UUID?
    public var name: String
    public var group: CategoryKind
    public var systemKey: String?
    public var sortOrder: Int
    public var isHidden: Bool

    public init(id: UUID = UUID(), type: CategoryType, parentID: UUID? = nil, name: String, group: CategoryKind,
                systemKey: String? = nil, sortOrder: Int = 0, isHidden: Bool = false) {
        self.id = id
        self.type = type
        self.parentID = parentID
        self.name = name
        self.group = group
        self.systemKey = systemKey
        self.sortOrder = sortOrder
        self.isHidden = isHidden
    }
}

/// The default tree (PRD Appendix A). Seeded once by the data layer; `systemKey`s let code find a
/// category after the user renames it. Never change an existing key.
public enum DefaultCategories {
    public struct Node: Sendable {
        public let key: String
        public let name: String
        public let group: CategoryKind
        public let type: CategoryType
        public let children: [(key: String, name: String)]
    }

    public static let adjustmentKey = "system.adjustment"

    public static let expense: [Node] = [
        node(.food, ["Groceries", "Dining out", "Food delivery", "Tea & snacks"]),
        node(.transport, ["Fuel", "Ride-hailing", "Parking & tolls", "Car maintenance", "Car installment"]),
        node(.housing, ["Rent", "Maintenance", "Furniture"]),
        node(.utilities, ["Electricity", "Gas", "Water", "Internet", "Mobile"]),
        node(.subscriptions, ["Streaming", "Software & AI tools", "Cloud storage", "Apps"]),
        node(.health, ["Doctor", "Medicine", "Lab tests"]),
        node(.personal, ["Clothing", "Grooming", "Gifts"]),
        node(.family, ["Family support", "Children", "Events"]),
        node(.education, ["Courses", "Books"]),
        node(.entertainment, ["Outings", "Games", "Travel"]),
        node(.financial, ["Bank fees", "Transfer fees", "Loan interest", "Kameti contribution"]),
        node(.office, ["Office rent", "Office utilities", "Staff salaries", "Office supplies", "Office refreshments", "Sales commission"]),
        node(.charity, ["Zakat", "Sadaqah", "Donations"]),
        node(.other, [])
    ]

    /// Income items are top level and share the Income colour; shown as "Income › Salary".
    public static let income: [Node] = [
        ("Salary", [String]()), ("Reimbursement", ["Office expense"]), ("Freelance / Business", []),
        ("Kameti payout", []), ("Refunds", []), ("Gifts", []), ("Other income", [])
    ].map { name, children in
        let key = "income." + slug(name)
        return Node(key: key, name: name, group: .income, type: .income,
                    children: children.map { (key + "." + slug($0), $0) })
    }

    public static let system: [Node] = [
        Node(key: adjustmentKey, name: "Balance adjustment", group: .other, type: .system, children: [])
    ]

    public static var all: [Node] { expense + income + system }

    /// "Office rent" → "office_rent"; "Software & AI tools" → "software_ai_tools".
    public static func slug(_ name: String) -> String {
        name.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : " " }
            .joined()
            .split(separator: " ")
            .joined(separator: "_")
    }

    private static func node(_ group: CategoryKind, _ children: [String]) -> Node {
        Node(key: group.rawValue, name: group.name, group: group, type: .expense,
             children: children.map { (group.rawValue + "." + slug($0), $0) })
    }
}

extension SpendCategory {
    public enum Problem: Error, Equatable, Sendable {
        case emptyName
        case nameTooLong
        case duplicateName
        /// Delete is blocked while transactions use it; merge instead (CAT-005).
        case inUse
        /// Merge needs two different categories of the same type.
        case invalidMerge
        case notFound
    }

    public static let maxNameLength = 30

    /// Checks a new or renamed category against its siblings (same parent), case- and space-insensitive.
    public static func validateName(_ name: String, siblingNames: [String]) throws(Problem) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .emptyName }
        guard trimmed.count <= maxNameLength else { throw .nameTooLong }
        let key = NameKey.make(trimmed)
        guard !siblingNames.contains(where: { NameKey.make($0) == key }) else { throw .duplicateName }
        return trimmed
    }

    /// Tags use the same rules with all tags as siblings.
    public static func validateTagName(_ name: String, existing: [String]) throws(Problem) -> String {
        try validateName(name, siblingNames: existing)
    }
}
