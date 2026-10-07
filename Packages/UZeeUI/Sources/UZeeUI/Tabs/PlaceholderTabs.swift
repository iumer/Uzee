import SwiftUI

/// Calendar (SCR-14). Month grid and due items arrive in M7.
struct CalendarTabView: View {
    var body: some View {
        TabPlaceholder(title: "Calendar") {
            EmptyStateView("Nothing due yet", systemImage: "calendar",
                           description: "Bills, subscriptions, installments and reminders will appear on their dates.")
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
