import Combine
import SwiftUI
import UZeeCore

/// App shell: four tabs, each with its own NavigationStack, and "+" in the middle of the bottom bar.
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
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// UZee's "try me" bubble, now and then.
    @State private var hint: String?
    /// The floating buttons step aside while the keyboard is up, so they never cover the field being typed in.
    @State private var isKeyboardUp = false

    public init(session: AppSession) {
        self.session = session
    }

    public var body: some View {
        TabView(selection: session.tabSelection) {
            // Home, Activity, +, Plan, People: "+" is the middle item, so it never pushes a tab into "More".
            Tab(AppTab.home.title, systemImage: AppTab.home.symbol, value: AppTab.home) { TabRoot(tab: .home, session: session) }
            Tab(AppTab.activity.title, systemImage: AppTab.activity.symbol, value: AppTab.activity) { TabRoot(tab: .activity, session: session) }
            // Choosing it opens Add (AppSession.tabSelection); on iPhone the big "+" below sits on top of it.
            // On iPhone it has no title, or its label would peek out under the big "+".
            Tab(sizeClass == .compact ? "" : AppTab.add.title, systemImage: "plus.circle.fill",
                value: AppTab.add) { Color.clear }
            Tab(AppTab.plan.title, systemImage: AppTab.plan.symbol, value: AppTab.plan) { TabRoot(tab: .plan, session: session) }
            Tab(AppTab.people.title, systemImage: AppTab.people.symbol, value: AppTab.people) { TabRoot(tab: .people, session: session) }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.never)
        .onAppear { Appearance.apply() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in isKeyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in isKeyboardUp = false }
        // iPhone: the big "+" sits in the middle of the bottom bar, over the Add item (owner, 2026-10-12).
        .overlay(alignment: .bottom) {
            if sizeClass == .compact, !isKeyboardUp {
                AddButton(isLarge: true) { session.addTapped() }
                    // Stay put when the keyboard opens instead of riding up over the fields.
                    .ignoresSafeArea(.keyboard)
            }
        }
        // UZee floats bottom right on every screen, just above the bottom bar, where "+" used to be (owner,
        // 2026-10-12). iPad has no bottom bar, so "+" floats under UZee there.
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: UZSpacing.m) {
                VoiceButton(hint: hint) { hint = nil; session.isVoicePresented = true }
                if sizeClass != .compact {
                    AddButton { session.addTapped() }
                }
            }
            .padding(.trailing, UZSpacing.xxl)
            .padding(.bottom, sizeClass == .compact ? 72 : UZSpacing.xxl)
            .ignoresSafeArea(.keyboard)
            .opacity(isKeyboardUp || session.hidesFloatingButtons ? 0 : 1)
            .allowsHitTesting(!isKeyboardUp && !session.hidesFloatingButtons)
        }
        .task { await showHints() }
        .sheet(isPresented: $session.isAddPresented) {
            // A shared expense opens the Splitwise-style sheet; everything else opens Add.
            if case .shared(let group, let person) = session.addRequest {
                SharedExpenseSheet(session: session, group: group, person: person).sessionErrors(session)
                    .interactiveDismissDisabled()
            } else if case .editShared(let transaction) = session.addRequest {
                SharedExpenseSheet(session: session, editing: transaction).sessionErrors(session)
                    .interactiveDismissDisabled()
            } else if case .sharedPrefill(let prefill) = session.addRequest {
                SharedExpenseSheet(session: session, prefill: prefill).sessionErrors(session)
                    .interactiveDismissDisabled()
            } else if case .repeatShared(let transaction) = session.addRequest {
                SharedExpenseSheet(session: session, copying: transaction).sessionErrors(session)
                    .interactiveDismissDisabled()
            } else {
                // Cancel or Save closes it; a stray swipe no longer loses what you typed (owner, 2026-10-14).
                AddSheet(session: session).sessionErrors(session)
                    .interactiveDismissDisabled()
            }
        }
        .sheet(isPresented: $session.isVoicePresented) {
            VoiceSheet(session: session).sessionErrors(session)
        }
        .sheet(isPresented: $session.isImportPresented) {
            ImportStatementView(session: session).sessionErrors(session)
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

    /// Every few hours of use, UZee pops up a friendly "try me" line for a few seconds (owner, 2026-10-12).
    /// Never during screen tests.
    private func showHints() async {
        guard !ProcessInfo.processInfo.arguments.contains("-uzee-in-memory") else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(25))
            let last = UserDefaults.standard.double(forKey: VoiceHint.lastShownKey)
            let quiet = Date().timeIntervalSince1970 - last > VoiceHint.gap
            if quiet, scenePhase == .active, !isLocked, !showingOnboarding, !session.isAddPresented, !session.isVoicePresented {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: VoiceHint.lastShownKey)
                withAnimation(.spring(duration: 0.5, bounce: 0.35)) { hint = VoiceHint.lines.randomElement() }
                try? await Task.sleep(for: .seconds(7))
                withAnimation(.easeOut(duration: 0.3)) { hint = nil }
            }
            try? await Task.sleep(for: .seconds(60))
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

/// The glass "+" that opens Add from any tab: big and green in the middle of the iPhone's bottom bar.
struct AddButton: View {
    var isLarge = false
    let action: () -> Void

    var body: some View {
        // The system glass button style keeps taps reliable; a custom interactive glass layer can swallow them.
        Button(action: action) {
            Image(systemName: AppTab.add.symbol)
                .font(isLarge ? .title.weight(.semibold) : .title2.weight(.semibold))
                .frame(width: isLarge ? 50 : 44, height: isLarge ? 50 : 44)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .keyboardShortcut("n", modifiers: .command)  // ⌘N on an iPad keyboard
        .accessibilityLabel(AppTab.add.title)
        .accessibilityIdentifier("tab.add")
    }
}

/// The singing UZee, bottom right on every screen: opens Ask UZee. Now and then a bubble says "try me".
struct VoiceButton: View {
    var hint: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: UZSpacing.s) {
            if let hint {
                Button(action: action) {
                    Text(hint)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(UZColor.label)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, UZSpacing.l)
                        .padding(.vertical, UZSpacing.m)
                        .frame(maxWidth: 230, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.4, anchor: .trailing).combined(with: .opacity))
                .accessibilityIdentifier("tab.voiceHint")
            }
            Button(action: action) {
                SingingMic(size: 40)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask UZee")
            .accessibilityIdentifier("tab.voice")
        }
    }
}

/// UZee's friendly nudges.
enum VoiceHint {
    static let lastShownKey = "uzee.voiceHint.lastShown"
    /// At most one nudge every 4 hours.
    static let gap: TimeInterval = 4 * 3600
    static let lines = [
        "Psst… need help with anything? Try me! 😊",
        "Spent something? Just tell me, I'll write it down ✍️",
        "Ask me \u{201C}how much did I spend on food?\u{201D} 🍔",
        "I don't bite, I only count! Tap me 💚",
        "Tired of typing? Say it and I'll do the rest 🎙️",
        "Wondering who owes you? Ask me 👀",
        "Bills coming up? I can tell you before they bite 🗓️",
    ]
}

/// One tab: its NavigationStack, its root screen, the sample banner and shared destinations.
struct TabRoot: View {
    let tab: AppTab
    @Bindable var session: AppSession

    var body: some View {
        NavigationStack(path: session.path(for: tab)) {
            screen
                // Settings sits behind the profile icon, always top right on every tab (owner, 2026-10-12); no tab puts
                // anything else on the right, so it never moves.
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: Route.settings) {
                            Image(systemName: "person.crop.circle").font(.title3)
                        }
                        .accessibilityLabel("Settings")
                        // Home keeps the plain id the screen tests use; other tabs get their own so ids never clash.
                        .accessibilityIdentifier(tab == .home ? "tab.settings" : "tab.settings.\(tab)")
                    }
                }
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
                    case .transaction(let id): EntryDestination(session: session, transactionID: id)
                    case .exchangeRate: ExchangeRateView(session: session)
                    case .recentlyDeleted: RecentlyDeletedView(session: session)
                    case .categories: CategoriesView(session: session)
                    case .tags: TagsView(session: session)
                    case .budgetLimits: BudgetLimitsView(session: session)
                    case .budgetCategory(let id, let start):
                        BudgetCategoryView(session: session, categoryID: id, periodStart: start)
                    case .person(let id): PersonDetailView(session: session, personID: id)
                    case .loan(let id): LoanDetailView(session: session, loanID: id)
                    case .groups: GroupsView(session: session)
                    case .group(let id): GroupDetailView(session: session, groupID: id)
                    case .bills: BillsHubView(session: session, tab: tab)
                    case .recurring(let id): RecurringDetailView(session: session, itemID: id)
                    case .reports: ReportsView(session: session)
                    case .prayer: PrayerView(session: session)
                    }
                }
        }
        // Room under the last row on every screen, so the floating UZee never covers an amount.
        // Room under the last card so it can always scroll clear of the floating UZee (BUG-017).
        .contentMargins(.bottom, 130, for: .scrollContent)
    }

    @ViewBuilder private var screen: some View {
        switch tab {
        case .home: HomeView(session: session)
        case .activity: ActivityView(session: session)
        case .plan: PlanView(session: session)
        case .people: PeopleView(session: session)
        case .add: EmptyView()
        }
    }
}
