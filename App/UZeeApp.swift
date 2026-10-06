import SwiftUI
import UZeeCore
import UZeeUI

@main
struct UZeeApp: App {
    @State private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            LaunchView(info: container.info, status: container.databaseStatus)
        }
    }
}
