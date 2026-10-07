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
                             sampleData: database.map(Self.sampleDataActions) ?? .unavailable)
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
}
