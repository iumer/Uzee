import Foundation
import UZeeCore

/// The five tabs in order (SCREEN_INVENTORY §1.1), plus the detached "+" item.
public enum AppTab: String, CaseIterable, Hashable, Sendable {
    case home, activity, budget, calendar, people
    /// Not a screen: selecting it opens the Add sheet and keeps the current tab.
    case add

    public static let screens: [AppTab] = [.home, .activity, .budget, .calendar, .people]

    public var title: String {
        switch self {
        case .home: "Home"
        case .activity: "Activity"
        case .budget: "Budget"
        case .calendar: "Calendar"
        case .people: "People"
        case .add: "Add"
        }
    }

    public var symbol: String {
        switch self {
        case .home: "house"
        case .activity: "list.bullet.rectangle"
        case .budget: "chart.pie"
        case .calendar: "calendar"
        case .people: "person.2"
        case .add: "plus"
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
}
