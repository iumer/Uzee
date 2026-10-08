import SwiftUI
import UZeeCore

/// App shell: five tabs, each with its own NavigationStack, plus the detached "+" (DESIGN_SYSTEM §9).
/// `.sidebarAdaptable` gives iPad a sidebar with the same destinations; compact widths keep the tab bar.
public struct RootView: View {
    @Bindable var session: AppSession
    /// The animated logo at launch; UI tests (-uzee-in-memory) skip it.
    @State private var showingSplash = !ProcessInfo.processInfo.arguments.contains("-uzee-in-memory")

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
        // Only on each tab's first screen; detail screens and Settings keep their full width.
        .overlay(alignment: .bottomTrailing) {
            if session.path(for: session.selectedTab).wrappedValue.isEmpty {
                AddButton { session.isAddPresented = true }
                    .padding(.trailing, UZSpacing.xxl)
                    .padding(.bottom, 72)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: session.path(for: session.selectedTab).wrappedValue.isEmpty)
        .sheet(isPresented: $session.isAddPresented) {
            AddSheet(session: session)
        }
        .sheet(isPresented: $session.isVoicePresented) {
            VoiceSheet(session: session)
        }
        .sheet(isPresented: $session.isImportPresented) {
            ImportStatementView(session: session)
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
        .toastOverlay(session.toasts)
        .overlay {
            if showingSplash {
                LaunchSplash(isShowing: $showingSplash).transition(.opacity)
            }
        }
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
                // Room under the last row so the floating "+" never covers an amount.
                .contentMargins(.bottom, 64, for: .scrollContent)
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
                    case .budgetLimits: BudgetLimitsView(session: session)
                    case .budgetCategory(let id, let start):
                        BudgetCategoryView(session: session, categoryID: id, periodStart: start)
                    case .person(let id): PersonDetailView(session: session, personID: id)
                    case .groups: GroupsView(session: session)
                    case .group(let id): GroupDetailView(session: session, groupID: id)
                    case .bills: BillsHubView(session: session, tab: tab)
                    case .recurring(let id): RecurringDetailView(session: session, itemID: id)
                    case .reports: ReportsView(session: session)
                    }
                }
        }
    }

    @ViewBuilder private var screen: some View {
        switch tab {
        case .home: HomeView(session: session)
        case .activity: ActivityView(session: session)
        case .budget: BudgetView(session: session)
        case .calendar: CalendarTabView(session: session)
        case .people: PeopleView(session: session)
        case .add: EmptyView()
        }
    }
}
