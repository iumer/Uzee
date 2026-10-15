import Foundation
import UZeeCore

/// The four screens plus "+" in the middle of the bottom bar (owner's round 3 pick M, 2026-10-12).
/// Plan holds Budget and Calendar behind one switch.
public enum AppTab: String, CaseIterable, Hashable, Sendable {
    case home, activity, plan, people
    /// Not a screen: selecting it opens the Add sheet and keeps the current tab.
    case add

    public static let screens: [AppTab] = [.home, .activity, .plan, .people]
    /// The bottom bar, left to right: "+" sits in the middle.
    public static let bar: [AppTab] = [.home, .activity, .add, .plan, .people]

    public var title: String {
        switch self {
        case .home: "Home"
        case .activity: "Activity"
        case .plan: "Plan"
        case .people: "People"
        case .add: "Add"
        }
    }

    public var symbol: String {
        switch self {
        case .home: "house"
        case .activity: "list.bullet.rectangle"
        case .plan: "calendar.badge.clock"
        case .people: "person.2"
        case .add: "plus"
        }
    }
}

/// The two halves of the Plan tab.
public enum PlanPart: String, CaseIterable, Hashable, Sendable {
    case month, budget, calendar

    public var title: String {
        switch self {
        case .month: "Month"
        case .budget: "Budget"
        case .calendar: "Calendar"
        }
    }
}

/// Pushed destinations. Each tab keeps its own path, so Back always works (AUD-14).
public enum Route: Hashable, Sendable {
    case settings
    case componentGallery
    case accounts
    case account(UUID)
    case transaction(UUID)
    case exchangeRate
    case recentlyDeleted
    case categories
    case tags
    case budgetLimits
    case budgetCategory(UUID, LocalDate)
    case person(UUID)
    case groups
    case group(UUID)
    case bills
    case recurring(UUID)
    case reports
    case prayer
}
