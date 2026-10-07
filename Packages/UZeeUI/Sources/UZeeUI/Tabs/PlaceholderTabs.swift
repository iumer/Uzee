import SwiftUI

/// Activity (SCR-08). The list, search and filters arrive with transactions (M2–M3).
struct ActivityView: View {
    var body: some View {
        TabPlaceholder(title: "Activity") {
            EmptyStateView("No transactions yet", systemImage: "list.bullet.rectangle",
                           description: "Everything you spend, earn and transfer will be listed here by day.")
        }
    }
}

/// Budget (SCR-11). Limits and progress arrive in M4.
struct BudgetView: View {
    var body: some View {
        TabPlaceholder(title: "Budget") {
            EmptyStateView("No budget for \(Date.now.formatted(.dateTime.month(.wide)))", systemImage: "chart.pie",
                           description: "Set a monthly total and limits per category. Your spending still counts while you decide.")
        }
    }
}

/// Calendar (SCR-14). Month grid and due items arrive in M7.
struct CalendarTabView: View {
    var body: some View {
        TabPlaceholder(title: "Calendar") {
            EmptyStateView("Nothing due yet", systemImage: "calendar",
                           description: "Bills, subscriptions, installments and reminders will appear on their dates.")
        }
    }
}

/// People (SCR-20). People, groups and balances arrive in M5.
struct PeopleView: View {
    var body: some View {
        TabPlaceholder(title: "People") {
            EmptyStateView("No people yet", systemImage: "person.2",
                           description: "Add someone you lend to, borrow from or split bills with. Each person gets one balance.")
        }
    }
}

/// Large-title tab root with grouped background and centred content.
struct TabPlaceholder<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .padding(.top, 48)
                .frame(maxWidth: .infinity)
        }
        .background(UZColor.bg)
        .navigationTitle(title)
        .accessibilityIdentifier("screen.\(title.lowercased())")
    }
}
