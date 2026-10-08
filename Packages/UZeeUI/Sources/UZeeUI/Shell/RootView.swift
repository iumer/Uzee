import SwiftUI
import UZeeCore

/// App shell: five tabs, each with its own NavigationStack, plus the detached "+" (DESIGN_SYSTEM §9).
/// `.sidebarAdaptable` gives iPad a sidebar with the same destinations; compact widths keep the tab bar.
public struct RootView: View {
    @Bindable var session: AppSession
    /// The animated logo at launch; UI tests (-uzee-in-memory) skip it.
    @State private var showingSplash = !ProcessInfo.processInfo.arguments.contains("-uzee-in-memory")
    /// First-launch setup, once the splash has gone.
    @State private var showingOnboarding = false
    /// Face ID lock (SEC-01): locked at launch and whenever UZee leaves the screen, when the owner turned it on.
    @State private var isLocked = AppLock.isOn
    @State private var isUnlocking = false
    /// Ask once per return; the Face ID prompt itself makes the app inactive, so a cancel mustn't re-prompt.
    @State private var promptOnActive = AppLock.isOn
    /// When UZee left the screen; it locks on return once the timeout has passed (SET-01).
    @State private var backgroundedAt: Date?
    @Environment(\.scenePhase) private var scenePhase

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
        .onAppear { Appearance.apply() }
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
        // The lock covers everything, sheets included; with the lock on, the app switcher shows no amounts (SET-02).
        .onChange(of: curtain, initial: true) { _, mode in
            LockCurtain.shared.show(mode, unlock: { unlock() }, unlockWithPasscode: { unlock(passcodeOnly: true) })
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .background:
                if AppLock.isOn, !isLocked { backgroundedAt = Date() }
            case .active:
                Appearance.apply()
                if let since = backgroundedAt, AppLock.isOn {
                    backgroundedAt = nil
                    if Date().timeIntervalSince(since) >= AppLock.timeout { isLocked = true; promptOnActive = true }
                }
                if isLocked, promptOnActive { promptOnActive = false; unlock() }
                session.rescheduleReminders()
                Task { await session.refreshWiseRates() }
            default: break
            }
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(session: session) { showingOnboarding = false }
        }
        .onChange(of: showingSplash, initial: true) { _, splash in
            if !splash, OnboardingView.isNeeded(session) { showingOnboarding = true }
        }
        .onChange(of: session.isOnboardingRequested) { _, requested in
            guard requested else { return }
            session.isOnboardingRequested = false
            showingOnboarding = true
        }
    }

    private var curtain: LockCurtain.Mode {
        if isLocked { return .locked }
        return AppLock.isOn && scenePhase != .active ? .privacy : .none
    }

    private func unlock(passcodeOnly: Bool = false) {
        guard !isUnlocking else { return }
        isUnlocking = true
        Task {
            let ok = passcodeOnly ? await AppLock.unlockWithPasscode() : await AppLock.unlock()
            isUnlocking = false
            if ok { withAnimation(.easeOut(duration: 0.25)) { isLocked = false } }
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
        .keyboardShortcut("n", modifiers: .command)  // ⌘N on an iPad keyboard
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
