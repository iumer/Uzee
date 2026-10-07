import SwiftUI
import UZeeUI

@main
struct UZeeApp: App {
    @State private var container = AppContainer.shared

    var body: some Scene {
        WindowGroup {
            RootView(session: container.session)
        }
    }
}
