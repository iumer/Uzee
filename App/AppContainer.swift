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

    init(info: AppInfo, database: AppDatabase?) {
        self.info = info
        self.database = database
        session = AppSession(info: info, isDatabaseReady: database != nil,
                             sampleData: database.map(Self.sampleDataActions) ?? .unavailable,
                             ledger: database.map(Self.ledgerClient) ?? .unavailable)
    }

    static func live() -> AppContainer {
        let info = AppInfo(infoDictionary: Bundle.main.infoDictionary)
        let arguments = ProcessInfo.processInfo.arguments
        do {
            // UI tests pass -uzee-in-memory so they never touch a real database.
            let database = arguments.contains("-uzee-in-memory") ? try AppDatabase.inMemory() : try AppDatabase.onDisk()
            let upToDate = try database.isUpToDate()
            Log.data.info("Database opened, migrations up to date: \(upToDate, privacy: .public)")
            return AppContainer(info: info, database: database)
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
