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
    public var isAddPresented = false {
        didSet { if !isAddPresented { addRequest = .new } }
    }
    /// What the Add sheet opens with: a blank expense, a transfer, an edit or a repeat (TXN-014).
    public var addRequest: AddRequest = .new
    public var isVoicePresented = false
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

    private let sampleData: SampleDataActions
    public let client: LedgerClient
    public let activity: ActivityClient

    public init(info: AppInfo, isDatabaseReady: Bool, sampleData: SampleDataActions, ledger: LedgerClient = .unavailable,
                activity: ActivityClient = .unavailable) {
        self.info = info
        self.isDatabaseReady = isDatabaseReady
        self.sampleData = sampleData
        self.client = ledger
        self.activity = activity
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
        } catch {
            errorMessage = "Couldn't read your accounts. Close UZee and open it again."
        }
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
            errorMessage = failure
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
            errorMessage = "Couldn't turn on sample data. Try again."
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
}
