import SwiftUI
import UZeeUI

@main
struct UZeeApp: App {
    @State private var container = AppContainer.shared

    var body: some Scene {
        WindowGroup {
            RootView(session: container.session)
                // uzee://ask from the Lock Screen widget opens Ask UZee.
                .onOpenURL { url in
                    if url.scheme == "uzee", url.host() == "ask" { container.session.openVoice() }
                }
        }
    }
}
