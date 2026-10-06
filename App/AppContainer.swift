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

    var databaseStatus: LaunchView.DatabaseStatus { database == nil ? .failed : .ready }

    init(info: AppInfo, database: AppDatabase?) {
        self.info = info
        self.database = database
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
}
