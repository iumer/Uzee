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
                             activity: activity)
    }

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
