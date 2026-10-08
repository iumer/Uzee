import SwiftUI
import UZeeCore

/// App-wide UI state: navigation per tab, sample mode, toasts. Data work is injected
/// as closures so UZeeUI stays independent of the database package (ARCHITECTURE layers).
@MainActor
@Observable
public final class AppSession {
    public struct SampleDataActions: Sendable {
        public var isActive: @Sendable () throws -> Bool
        public var load: @Sendable () throws -> Void
        public var removeAll: @Sendable () throws -> Int

        public init(isActive: @escaping @Sendable () throws -> Bool,
                    load: @escaping @Sendable () throws -> Void,
                    removeAll: @escaping @Sendable () throws -> Int) {
            self.isActive = isActive
            self.load = load
            self.removeAll = removeAll
        }

        /// No database: sample mode stays off.
        public static let unavailable = SampleDataActions(isActive: { false }, load: {}, removeAll: { 0 })
    }

    public let info: AppInfo
    public let isDatabaseReady: Bool
    public let toasts = ToastCenter()

    public var selectedTab: AppTab = .home
    public var paths: [AppTab: [Route]] = [:]
    /// A day the Calendar should jump to (from a reminder).
    public var calendarFocus: LocalDate?
    public var isAddPresented = false {
        didSet { if !isAddPresented { addRequest = .new } }
    }
    /// What the Add sheet opens with: a blank expense, a transfer, an edit or a repeat (TXN-014).
    public var addRequest: AddRequest = .new
    public var isVoicePresented = false {
        didSet { if !isVoicePresented { voiceRequest = nil } }
    }
    /// A sentence to handle as soon as Ask UZee opens (from Siri "Add to UZee").
    public var voiceRequest: String?
    /// Statement import (SCR-34), opened from Settings or an account.
    public var importAccountID: UUID?
    public var isImportPresented = false
    public private(set) var isSampleMode = false
    /// Last error shown to the user, in plain words (DESIGN_SYSTEM §15).
    public var errorMessage: String?

    /// Accounts, balances, categories and rates as of the last change.
    public private(set) var ledger: LedgerSnapshot = .empty()
    /// Non-deleted transactions, newest first.
    public private(set) var transactions: [MoneyTransaction] = []
    /// All tags, and each transaction's tags (CAT-006).
    public private(set) var tags: [MoneyTag] = []
    public private(set) var tagMap: [UUID: Set<UUID>] = [:]
    /// Transactions with a receipt, for the paperclip on rows.
    public private(set) var withReceipts: Set<UUID> = []
    /// Activity search and filters survive tab switches.
    public var activityFilter = ActivityFilter()
    /// People, groups, splits and loans, and the balances computed from them (SPL-07).
    public private(set) var people: PeopleSnapshot = .empty
    public private(set) var balances = PeopleLedger(selfID: UUID(), transactions: [], splits: [], loans: [], base: .pkr, rates: [:])
    /// Bills, subscriptions, income and plans with their resolved occurrences (REC-02).
    public private(set) var recurring: RecurringSnapshot = .empty
    /// Custom calendar entries (CAL-03) and reminder preferences (CAL-04).
    public private(set) var events: [CalendarEvent] = []
    public private(set) var reminderSettings: ReminderSettings = .standard
    private var scheduling: Task<Void, Never>?

    private let sampleData: SampleDataActions
    public let client: LedgerClient
    public let activity: ActivityClient
    public let budgets: BudgetClient
    public let peopleClient: PeopleClient
    public let recurringClient: RecurringClient
    public let smart: SmartClient
    public let calendar: CalendarClient

    public init(info: AppInfo, isDatabaseReady: Bool, sampleData: SampleDataActions, ledger: LedgerClient = .unavailable,
                activity: ActivityClient = .unavailable, budgets: BudgetClient = .unavailable, people: PeopleClient = .unavailable,
                recurring: RecurringClient = .unavailable, smart: SmartClient = .unavailable, calendar: CalendarClient = .unavailable) {
        self.info = info
        self.isDatabaseReady = isDatabaseReady
        self.sampleData = sampleData
        self.client = ledger
        self.activity = activity
        self.budgets = budgets
        self.peopleClient = people
        self.recurringClient = recurring
        self.smart = smart
        self.calendar = calendar
        isSampleMode = (try? sampleData.isActive()) ?? false
        reload()
    }

    /// Re-reads the ledger after any change; balances are always derived, never cached (ACC-03).
    public func reload() {
        do {
            ledger = try client.snapshot()
            transactions = try client.transactions()
            tags = try activity.tags()
            tagMap = try activity.tagMap()
            withReceipts = try activity.withAttachments()
            people = try peopleClient.snapshot()
            balances = PeopleLedger(selfID: people.selfID, transactions: transactions, splits: people.splits, loans: people.loans,
                                    base: ledger.base, rates: ledger.rates)
            recurring = try recurringClient.snapshot()
            events = try calendar.events()
            reminderSettings = try calendar.reminderSettings()
        } catch {
            errorMessage = "Couldn't read your accounts. Close UZee and open it again."
        }
        rescheduleReminders()
    }

    /// Re-plans every reminder from the current data (on launch, after each change and on return to the app).
    /// Coalesced, so a burst of saves schedules once.
    public func rescheduleReminders() {
        scheduling?.cancel()
        let plan = ReminderPlanner.plan(recurring: recurring, events: events, loans: loanReminders, settings: reminderSettings,
                                        today: today, minuteNow: Self.minuteNow(), format: { MoneyFormatter.string($0) })
        let calendar = calendar
        scheduling = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await calendar.schedule(plan)
        }
    }

    static func minuteNow() -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Open loans with a due date (LOAN-07).
    private var loanReminders: [(name: String, outstanding: Money, due: LocalDate, owedToMe: Bool)] {
        people.loans.compactMap { loan in
            guard let due = loan.dueDate, let name = people.person(loan.personID)?.name ?? loan.institution else { return nil }
            let outstanding = LoanCalculator.outstanding(loan)
            guard outstanding.minorUnits > 0 else { return nil }
            return (name, outstanding, due, loan.direction == .lent)
        }
    }

    public func saveEvent(_ event: CalendarEvent) -> Bool {
        do {
            try calendar.saveEvent(event)
            reload()
            Task { _ = await calendar.requestNotifications(); rescheduleReminders() }
            return true
        } catch {
            errorMessage = "Couldn't save this. Check the title and amount."
            return false
        }
    }

    public func deleteEvent(_ id: UUID) {
        do {
            try calendar.deleteEvent(id)
            reload()
            toasts.show("Deleted")
        } catch {
            errorMessage = "Couldn't delete this. Try again."
        }
    }

    public func setReminderSettings(_ settings: ReminderSettings) {
        do {
            try calendar.setReminderSettings(settings)
            reload()
        } catch {
            errorMessage = "Couldn't save reminder settings."
        }
    }

    /// Opens Ask UZee, optionally with a sentence to handle right away.
    public func openVoice(_ request: String? = nil) {
        isAddPresented = false
        voiceRequest = request
        isVoicePresented = true
    }

    /// Opens statement import, into `account` when given.
    public func openImport(account: UUID? = nil) {
        importAccountID = account
        isImportPresented = true
    }

    /// Opens the Add sheet for something specific.
    public func openAdd(_ request: AddRequest) {
        addRequest = request
        isAddPresented = true
    }

    /// Saves a new or edited transaction, then offers Undo for 5 seconds (AUD-13, TXN-013).
    @discardableResult
    public func save(_ transaction: MoneyTransaction, isNew: Bool) -> Bool {
        let previous = isNew ? nil : transactions.first { $0.id == transaction.id }
        do {
            try client.save(transaction)
        } catch {
            errorMessage = "Couldn't save. Nothing was changed. Try again."
            return false
        }
        reload()
        toasts.show(isNew ? "Saved" : "Changes saved") { [weak self] in
            guard let self else { return }
            do {
                if let previous { try self.client.save(previous) } else { try self.client.discard(transaction.id) }
            } catch {
                self.errorMessage = "Couldn't undo. Your entry is still saved."
            }
            self.reload()
        }
        return true
    }

    /// Saves a transaction with its split (SPL-03), then offers Undo like `save`.
    @discardableResult
    public func save(_ transaction: MoneyTransaction, split: Split?, isNew: Bool) -> Bool {
        let previous = isNew ? nil : transactions.first { $0.id == transaction.id }
        let previousSplit = people.split(for: transaction.id)
        do {
            try peopleClient.saveSplit(transaction, split)
        } catch let problem as SplitProblem {
            errorMessage = SplitText.problem(problem)
            return false
        } catch {
            errorMessage = "Couldn't save. Nothing was changed. Try again."
            return false
        }
        reload()
        toasts.show(isNew ? "Saved" : "Changes saved") { [weak self] in
            guard let self else { return }
            do {
                if let previous { try self.peopleClient.saveSplit(previous, previousSplit) } else { try self.client.discard(transaction.id) }
            } catch {
                self.errorMessage = "Couldn't undo. Your entry is still saved."
            }
            self.reload()
        }
        return true
    }

    /// Today in the device time zone, for due states.
    public var today: LocalDate { LocalDate(Date(), in: .current) }

    /// Mark paid (REC-02): posts the payment once, then offers Undo, which removes it and makes the bill due again.
    @discardableResult
    public func markPaid(_ occurrence: Occurrence, amount: Money, account: UUID?, date: Date) -> Bool {
        let item = occurrence.itemID, scheduled = occurrence.scheduledDate
        let transactionID: UUID
        do {
            transactionID = try recurringClient.markPaid(item, scheduled, amount, account, date)
        } catch {
            errorMessage = "Couldn't mark it paid. Nothing was changed. Try again."
            return false
        }
        reload()
        toasts.show("Marked paid") { [weak self] in
            guard let self else { return }
            do {
                try self.recurringClient.reopen(item, scheduled)
                try self.client.discard(transactionID)
            } catch {
                self.errorMessage = "Couldn't undo. The payment is still saved."
            }
            self.reload()
        }
        return true
    }

    // MARK: Notification actions (CAL-05)

    /// "Mark paid" on a bill reminder: posts exactly one payment from the bill's account, at the expected amount.
    /// Without an account (or if it fails) the bill opens instead, so nothing is posted to the wrong place.
    public func markPaidFromReminder(item: UUID, scheduled: LocalDate) {
        reload()
        guard let bill = recurring.item(item), bill.accountID != nil || bill.paidByID != nil,
              (try? recurringClient.markPaid(item, scheduled, bill.amount(on: scheduled), bill.accountID, Date())) != nil else {
            openReminder(item: item, date: scheduled)
            return
        }
        reload()
        toasts.show("\(bill.name) marked paid")
    }

    /// "Snooze 1 day" on a bill reminder: the bill moves to tomorrow and gets a fresh reminder.
    public func snoozeFromReminder(item: UUID, scheduled: LocalDate) {
        let until = max(today, scheduled).addingDays(1)
        do {
            try recurringClient.snooze(item, scheduled, until)
        } catch {
            openReminder(item: item, date: scheduled)
            return
        }
        reload()
    }

    /// Tapping a reminder opens the bill (or the Calendar on that day).
    public func openReminder(item: UUID?, date: LocalDate?) {
        selectedTab = .calendar
        if let item, recurring.item(item) != nil {
            paths[.calendar] = [.bills, .recurring(item)]
        } else {
            paths[.calendar] = []
            calendarFocus = date
        }
    }

    /// Skip this time or snooze (REC-08), with Undo.
    public func skip(_ occurrence: Occurrence) {
        resolve(occurrence, toast: "Skipped this time") { try $0.skip(occurrence.itemID, occurrence.scheduledDate) }
    }

    public func snooze(_ occurrence: Occurrence, days: Int = 1) {
        let until = max(today, occurrence.dueDate).addingDays(days)
        resolve(occurrence, toast: "Snoozed to \(DateText.short(until))") {
            try $0.snooze(occurrence.itemID, occurrence.scheduledDate, until)
        }
    }

    private func resolve(_ occurrence: Occurrence, toast: String, _ work: (RecurringClient) throws -> Void) {
        guard perform("Couldn't change it. Try again.", { try work(recurringClient) }) else { return }
        toasts.show(toast) { [weak self] in
            guard let self else { return }
            self.perform("Couldn't undo. Try again.") { try self.recurringClient.reopen(occurrence.itemID, occurrence.scheduledDate) }
        }
    }

    /// Soft delete; the row can come back from Recently Deleted (TXN-008, DATA-011).
    public func delete(_ transaction: MoneyTransaction) {
        do {
            try client.delete(transaction.id)
        } catch {
            errorMessage = "Couldn't delete. Nothing was changed. Try again."
            return
        }
        reload()
        toasts.show("Deleted") { [weak self] in
            self?.restore(transaction.id, announce: false)
        }
    }

    /// Brings a deleted transaction back with its legs, tags and receipts.
    public func restore(_ id: UUID, announce: Bool = true) {
        if perform("Couldn't restore. Try again.", { try activity.restore(id) }), announce {
            toasts.show("Restored")
        }
    }

    /// Runs an account change and refreshes; returns false and explains when it fails.
    @discardableResult
    public func perform(_ failure: String, _ work: () throws -> Void) -> Bool {
        do {
            try work()
            reload()
            return true
        } catch {
            #if DEBUG
            errorMessage = "\(failure) [\(error)]"
            #else
            errorMessage = failure
            #endif
            return false
        }
    }

    /// Binding for the TabView: choosing "+" opens the Add sheet instead of switching tabs.
    public var tabSelection: Binding<AppTab> {
        Binding(
            get: { self.selectedTab },
            set: { newValue in
                if newValue == .add {
                    self.isAddPresented = true
                } else {
                    self.selectedTab = newValue
                }
            }
        )
    }

    public func path(for tab: AppTab) -> Binding<[Route]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    public func turnOnSampleData() {
        do {
            try sampleData.load()
            isSampleMode = true
            reload()
            toasts.show("Sample data on")
        } catch {
            #if DEBUG
            errorMessage = "Couldn't turn on sample data. \(error)"
            #else
            errorMessage = "Couldn't turn on sample data. Try again."
            #endif
        }
    }

    public func removeSampleData() {
        do {
            _ = try sampleData.removeAll()
            isSampleMode = false
            reload()
            toasts.show("Sample data removed")
        } catch {
            errorMessage = "Couldn't remove sample data. Nothing was changed. Try again."
        }
    }
}

/// How the Add sheet starts.
public enum AddRequest: Equatable, Sendable {
    case new
    case transfer
    case edit(MoneyTransaction)
    /// "Repeat this": same details, today's date, a new transaction (TXN-014).
    case repeatOf(MoneyTransaction)
    /// "Add shared expense" from People: an expense split with a group or a person (SPL-03).
    case shared(group: UUID?, person: UUID?)
}
