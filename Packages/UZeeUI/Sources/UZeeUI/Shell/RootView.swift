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
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.never)
        // A sixth Tab would push People into "More" on iPhone, so "+" floats above the tab bar instead.
        .overlay(alignment: .bottomTrailing) {
            AddButton { session.isAddPresented = true }
                .padding(.trailing, UZSpacing.xxl)
                .padding(.bottom, 72)
        }
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

/// The floating glass "+" that opens Add from any tab.
struct AddButton: View {
    let action: () -> Void

    var body: some View {
        // The system glass button style keeps taps reliable; a custom interactive glass layer can swallow them.
        Button(action: action) {
            Image(systemName: AppTab.add.symbol)
                .font(.title2.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .accessibilityLabel(AppTab.add.title)
        .accessibilityIdentifier("tab.add")
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
                    case .accounts: AccountsView(session: session)
                    case .account(let id): AccountDetailView(session: session, accountID: id)
                    case .transaction(let id): TransactionDetailView(session: session, transactionID: id)
                    case .exchangeRate: ExchangeRateView(session: session)
                    case .recentlyDeleted: RecentlyDeletedView(session: session)
                    case .categories: CategoriesView(session: session)
                    case .tags: TagsView(session: session)
                    }
                }
        }
    }

    @ViewBuilder private var screen: some View {
        switch tab {
        case .home: HomeView(session: session)
        case .activity: ActivityView(session: session)
        case .budget: BudgetView()
        case .calendar: CalendarTabView()
        case .people: PeopleView()
        case .add: EmptyView()
        }
    }
}
