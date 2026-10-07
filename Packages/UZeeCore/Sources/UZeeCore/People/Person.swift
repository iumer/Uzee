import Foundation

/// One person (DATA_MODEL §3.13). Exactly one live row is "You" (`isSelf`); names need not be unique.
public struct Person: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var phone: String?
    public var notes: String?
    public var isSelf: Bool
    public var archivedAt: Date?
    public var isSample: Bool

    public init(id: UUID = UUID(), name: String, phone: String? = nil, notes: String? = nil, isSelf: Bool = false,
                archivedAt: Date? = nil, isSample: Bool = false) {
        self.id = id
        self.name = name
        self.phone = phone
        self.notes = notes
        self.isSelf = isSelf
        self.archivedAt = archivedAt
        self.isSample = isSample
    }

    /// First letter for the avatar ("U" for Usama, "O" for Office partner).
    public var initial: String { name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?" }

    public enum Problem: Error, Equatable, Sendable {
        case emptyName
        case nameTooLong
        /// A person with a balance or open loans is archived, never deleted.
        case hasBalance
        case notFound
    }

    public static let maxNameLength = 60

    public static func validateName(_ name: String) throws(Problem) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .emptyName }
        guard trimmed.count <= maxNameLength else { throw .nameTooLong }
        return trimmed
    }
}

/// Group icons offered when creating a group (mockup ICON_LIST).
public enum GroupIcon: String, CaseIterable, Sendable, Codable {
    case people, home, trip, office, food

    public var label: String {
        switch self {
        case .people: "People"
        case .home: "Home"
        case .trip: "Trip"
        case .office: "Work"
        case .food: "Food"
        }
    }

    public var symbolName: String {
        switch self {
        case .people: "person.2.fill"
        case .home: "house.fill"
        case .trip: "airplane"
        case .office: "building.2.fill"
        case .food: "fork.knife"
        }
    }

    public var colorHex: String {
        switch self {
        case .people: "#8E8E93"
        case .home: "#34C759"
        case .trip: "#FF9500"
        case .office: "#5856D6"
        case .food: "#FF2D55"
        }
    }
}

/// A group of people who share expenses (DATA_MODEL §3.14). `memberIDs` keeps member order, "You" first;
/// that order decides who gets leftover paisa in an equal split.
public struct SplitGroup: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var icon: GroupIcon
    public var memberIDs: [UUID]
    public var defaultMethod: SplitMethod
    public var simplifyDebts: Bool
    public var archivedAt: Date?
    public var isSample: Bool

    public init(id: UUID = UUID(), name: String, icon: GroupIcon = .people, memberIDs: [UUID],
                defaultMethod: SplitMethod = .equal, simplifyDebts: Bool = true, archivedAt: Date? = nil, isSample: Bool = false) {
        self.id = id
        self.name = name
        self.icon = icon
        self.memberIDs = memberIDs
        self.defaultMethod = defaultMethod
        self.simplifyDebts = simplifyDebts
        self.archivedAt = archivedAt
        self.isSample = isSample
    }
}
