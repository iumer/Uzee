import SwiftUI
import UZeeCore

/// App shell: five tabs, each with its own NavigationStack, plus the detached "+" (DESIGN_SYSTEM §9).
/// `.sidebarAdaptable` gives iPad a sidebar with the same destinations; compact widths keep the tab bar.
public struct RootView: View {
    @Bindable var session: AppSession

    public init(session: AppSession) {
        self.session = session
    }

    public var body: some View {
        TabView(selection: session.tabSelection) {
            ForEach(AppTab.screens, id: \.self) { tab in
                Tab(tab.title, systemImage: tab.symbol, value: tab) {
                    TabRoot(tab: tab, session: session)
                }
            }
            // iOS 26 shows the search-role tab detached at the trailing end: our "+" button.
            Tab(AppTab.add.title, systemImage: AppTab.add.symbol, value: AppTab.add, role: .search) {
                Color.clear
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.never)
        .sheet(isPresented: $session.isAddPresented) {
            AddSheet(session: session)
        }
        .sheet(isPresented: $session.isVoicePresented) {
            VoiceSheet()
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
        .toastOverlay(session.toasts)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })
    }
}

/// One tab: its NavigationStack, its root screen, the sample banner and shared destinations.
struct TabRoot: View {
    let tab: AppTab
    @Bindable var session: AppSession

    var body: some View {
        NavigationStack(path: session.path(for: tab)) {
            screen
                .safeAreaInset(edge: .top, spacing: 0) {
                    if session.isSampleMode {
                        SampleBanner { session.removeSampleData() }
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .settings: SettingsView(session: session)
                    case .componentGallery: ComponentGallery(session: session)
                    }
                }
        }
    }

    @ViewBuilder private var screen: some View {
        switch tab {
        case .home: HomeView(session: session)
        case .activity: ActivityView()
        case .budget: BudgetView()
        case .calendar: CalendarTabView()
        case .people: PeopleView()
        case .add: EmptyView()
        }
    }
}
