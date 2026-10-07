/// Top-level categories (PRD Appendix A). Colour and symbol belong to the top level and
/// subcategories inherit them (DESIGN_SYSTEM §2). Raw values are stored, so never rename them.
public enum CategoryKind: String, CaseIterable, Sendable, Codable {
    case office, transport, food, personal, utilities, subscriptions, financial, health, income
    case transfer, people
    case housing, family, education, entertainment, charity, other

    public var name: String {
        switch self {
        case .office: "Office"
        case .transport: "Transport"
        case .food: "Food"
        case .personal: "Personal"
        case .utilities: "Utilities"
        case .subscriptions: "Subscriptions"
        case .financial: "Financial"
        case .health: "Health"
        case .income: "Income"
        case .transfer: "Transfer"
        case .people: "People & loans"
        case .housing: "Housing"
        case .family: "Family"
        case .education: "Education"
        case .entertainment: "Entertainment"
        case .charity: "Charity"
        case .other: "Other"
        }
    }

    /// SF Symbol name (a plain string, so the domain layer stays UI-free).
    public var symbolName: String {
        switch self {
        case .office: "building.2.fill"
        case .transport: "car.fill"
        case .food: "fork.knife"
        case .personal: "bag.fill"
        case .utilities: "bolt.fill"
        case .subscriptions: "arrow.triangle.2.circlepath"
        case .financial: "banknote.fill"
        case .health: "cross.case.fill"
        case .income: "arrow.down.circle.fill"
        case .transfer: "arrow.left.arrow.right"
        case .people: "person.2.fill"
        case .housing: "house.fill"
        case .family: "figure.2.and.child.holdinghands"
        case .education: "book.fill"
        case .entertainment: "ticket.fill"
        case .charity: "hand.raised.fill"
        case .other: "ellipsis.circle.fill"
        }
    }
}
