import Foundation
import Observation
import UZeeCore
import UZeeData
import UZeeSystem
import UZeeUI

/// Composition root: builds the database and services once at launch
/// and hands them to the UI. The only long-lived shared object.
@MainActor
@Observable
final class AppContainer {
    let info: AppInfo
    let database: AppDatabase?
    let session: AppSession

    init(info: AppInfo, database: AppDatabase?, files: AttachmentStore? = nil) {
        self.info = info
        self.database = database
        var activity = ActivityClient.unavailable
        if let database, let files {
            Self.cleanUp(database, files)
            activity = Self.activityClient(database, files)
        }
        session = AppSession(info: info, isDatabaseReady: database != nil,
                             sampleData: database.map(Self.sampleDataActions) ?? .unavailable,
                             ledger: database.map(Self.ledgerClient) ?? .unavailable,
                             activity: activity,
                             budgets: database.map(Self.budgetClient) ?? .unavailable,
                             people: database.map(Self.peopleClient) ?? .unavailable,
                             recurring: database.map(Self.recurringClient) ?? .unavailable,
                             smart: Self.smartClient())
    }

    /// The one container, shared by the app scene and Siri (App Intents run in the app's process).
    static let shared = AppContainer.live()

    static func live() -> AppContainer {
        let info = AppInfo(infoDictionary: Bundle.main.infoDictionary)
        let arguments = ProcessInfo.processInfo.arguments
        do {
            // UI tests pass -uzee-in-memory so they never touch a real database.
            let inMemory = arguments.contains("-uzee-in-memory")
            let database = inMemory ? try AppDatabase.inMemory() : try AppDatabase.onDisk()
            let upToDate = try database.isUpToDate()
            Log.data.info("Database opened, migrations up to date: \(upToDate, privacy: .public)")
            let files = inMemory ? try AttachmentStore.temporary() : try AttachmentStore.onDisk()
            return AppContainer(info: info, database: database, files: files)
        } catch {
            Log.data.error("Database failed to open: \(String(describing: error), privacy: .private)")
            return AppContainer(info: info, database: nil)
        }
    }

    /// Vision, PDFKit, Speech and Foundation Models adapters from UZeeSystem (M9, M10).
    static func smartClient() -> SmartClient {
        SmartClient(
            readReceipt: { try ReceiptTextReader.lines(from: $0) },
            readStatement: { url, password in
                switch try StatementTextReader.read(url, password: password) {
                case .pdf(let versions): .pdf(versions)
                case .csv(let text): .csv(text)
                }
            },
            understand: { text, vocabulary, today in
                await VoiceUnderstanding.understand(text, vocabulary: vocabulary, today: today)
            },
            voiceModelProblem: { VoiceUnderstanding.modelProblem() },
            requestSpeechAccess: { await SpeechListener.requestAccess() },
            startListening: { try SpeechListener.shared.start($0) },
            stopListening: { SpeechListener.shared.stop() },
            cancelListening: { SpeechListener.shared.cancel() })
    }

    private static func sampleDataActions(_ database: AppDatabase) -> AppSession.SampleDataActions {
        let settings = DeviceSettingsStore(database: database)
        let sampleData = SampleDataService(database: database)
        return AppSession.SampleDataActions(
            isActive: { try settings.isSampleModeActive() },
            load: { try sampleData.load() },
            removeAll: {
                let removed = try sampleData.removeAll()
                Log.data.info("Sample data removed: \(removed, privacy: .public) rows")
                return removed
            }
        )
    }

    private static func ledgerClient(_ database: AppDatabase) -> LedgerClient {
        let store = LedgerStore(database: database)
        return LedgerClient(
            snapshot: { try store.snapshot() },
            transactions: { try store.transactions() },
            lastUsedAccountID: { try store.lastUsedAccountID() },
            save: { transaction in
                try store.save(transaction)
                Log.data.info("Transaction saved: \(transaction.kind.rawValue, privacy: .public)")
            },
            delete: { try store.delete(transactionID: $0) },
            discard: { try store.discard(transactionID: $0) },
            createAccount: { new in
                try Self.mapped {
                    try store.createAccount(name: new.name, kind: new.kind, currency: new.currency, openingBalance: new.openingBalance,
                                            openingDate: new.openingDate, includeInTotals: new.includeInTotals)
                }
            },
            updateAccount: { account in try Self.mapped { try store.updateAccount(account) } },
            setArchived: { archived, id in try store.setArchived(archived, accountID: id) },
            deleteAccount: { try store.deleteAccount(id: $0) },
            hasTransactions: { try store.hasTransactions(accountID: $0) },
            setRate: { rate, currency in try store.setRate(rate, for: currency) }
        )
    }

    /// Launch housekeeping: purge Recently Deleted items older than 30 days and stray receipt files (DATA-012).
    private static func cleanUp(_ database: AppDatabase, _ files: AttachmentStore) {
        let store = LedgerStore(database: database)
        do {
            files.remove(try store.purgeDeleted())
            files.removeOrphans(keeping: try store.attachmentFileNames())
        } catch {
            Log.data.error("Launch clean-up failed: \(String(describing: error), privacy: .private)")
        }
    }

    private static func budgetClient(_ database: AppDatabase) -> BudgetClient {
        let store = BudgetStore(database: database)
        return BudgetClient(
            settings: {
                let settings = try store.settings()
                return (settings.periodKind, settings.warnPercent)
            },
            setSettings: { kind, warn in try store.setSettings(.init(periodKind: kind, warnPercent: warn)) },
            plan: { try store.plan(for: $0) },
            existingPlans: { try store.existingPlans() },
            save: { try store.save($0) },
            firedAlerts: { try store.firedAlerts() },
            markFired: { try store.markFired($0) }
        )
    }

    private static func peopleClient(_ database: AppDatabase) -> PeopleClient {
        let store = PeopleStore(database: database)
        @Sendable func day(_ date: Date) -> LocalDate { LocalDate(date, in: .current) }
        return PeopleClient(
            snapshot: { try store.snapshot() },
            createPerson: { name, phone in try store.createPerson(name: name, phone: phone) },
            updatePerson: { try store.updatePerson($0) },
            createGroup: { name, icon, members, method in try store.createGroup(name: name, icon: icon, memberIDs: members, method: method) },
            updateGroup: { try store.updateGroup($0) },
            saveSplit: { transaction, split in try store.save(transaction, split: split) },
            recordLoan: { direction, person, amount, account, date, due, note in
                try store.recordLoan(direction: direction, personID: person, amount: amount, accountID: account, on: day(date),
                                     at: date, dueDate: due, note: note)
            },
            recordRepayment: { loan, amount, account, date in
                try store.recordRepayment(loanID: loan, amount: amount, accountID: account, on: day(date), at: date)
            },
            setWrittenOff: { writtenOff, loan in try store.setWrittenOff(writtenOff, loanID: loan) },
            setDueDate: { due, interest, loan in try store.setDueDate(due, interestBasisPoints: interest, loanID: loan) },
            addExistingBalances: { rows in try store.addExistingBalances(rows, on: day(Date())) },
            settle: { person, group, amount, iPaid, account, date in
                try store.settle(personID: person, groupID: group, amount: amount, iPaid: iPaid, accountID: account, on: day(date), at: date)
            }
        )
    }

    private static func recurringClient(_ database: AppDatabase) -> RecurringClient {
        let store = RecurringStore(database: database)
        @Sendable func day(_ date: Date) -> LocalDate { LocalDate(date, in: .current) }
        return RecurringClient(
            snapshot: { try store.snapshot() },
            save: { item, from in try store.save(item, priceFrom: from) },
            delete: { try store.delete(itemID: $0) },
            setStatus: { status, item in try store.setStatus(status, itemID: item, on: day(Date())) },
            markPaid: { item, scheduled, amount, account, date in
                let transaction = try store.markPaid(itemID: item, scheduledDate: scheduled, amount: amount, accountID: account,
                                                     on: day(date), at: date)
                Log.data.info("Recurring marked paid: \(transaction.kind.rawValue, privacy: .public)")
                return transaction.id
            },
            skip: { item, scheduled in try store.skip(itemID: item, scheduledDate: scheduled) },
            snooze: { item, scheduled, until in try store.snooze(itemID: item, scheduledDate: scheduled, until: until) },
            reopen: { item, scheduled in try store.reopen(itemID: item, scheduledDate: scheduled) },
            recordPayout: { payout, account, date in try store.recordPayout(payoutID: payout, accountID: account, on: day(date), at: date) }
        )
    }

    private static func activityClient(_ database: AppDatabase, _ files: AttachmentStore) -> ActivityClient {
        let store = LedgerStore(database: database)
        return ActivityClient(
            deletedTransactions: { try store.deletedTransactions() },
            restore: { try store.restore(transactionID: $0) },
            purge: { ids in files.remove(try store.purgeDeleted(only: ids)) },
            createCategory: { name, parent in try store.createCategory(name: name, parentID: parent) },
            renameCategory: { id, name in try store.renameCategory(id: id, to: name) },
            setCategoryHidden: { hidden, id in try store.setCategoryHidden(hidden, id: id) },
            reorderCategories: { try store.reorderCategories($0) },
            deleteCategory: { try store.deleteCategory(id: $0) },
            mergeCategory: { source, target in try store.mergeCategory(source, into: target) },
            categoryUsage: { try store.categoryUsage() },
            rememberedCategories: { try store.rememberedCategories() },
            tags: { try store.tags() },
            createTag: { try store.createTag(name: $0) },
            deleteTag: { try store.deleteTag(id: $0) },
            tagMap: { try store.tagMap() },
            setTags: { tags, id in try store.setTags(tags, transactionID: id) },
            attachments: { try store.attachments(transactionID: $0) },
            withAttachments: { try store.transactionsWithAttachments() },
            addAttachment: { transactionID, kind, data in
                let name = try files.write(data, kind: kind)
                let file = ReceiptFile(transactionID: transactionID, kind: kind, fileName: name, byteCount: Int64(data.count))
                do { try store.addAttachment(file) } catch { files.remove([name]); throw error }
                Log.data.info("Receipt attached: \(kind.rawValue, privacy: .public)")
                return file
            },
            removeAttachment: { id in
                if let name = try store.removeAttachment(id: id) { files.remove([name]) }
            },
            fileURL: { files.url(for: $0.fileName) }
        )
    }

    /// Store problems become the shared account problems the UI explains (ACC-008).
    private nonisolated static func mapped<T>(_ work: () throws -> T) throws -> T {
        do { return try work() } catch let problem as LedgerStore.Problem {
            switch problem {
            case .duplicateName: throw Account.Problem.duplicateName
            case .currencyLocked: throw Account.Problem.currencyLocked
            default: throw problem
            }
        }
    }
}
