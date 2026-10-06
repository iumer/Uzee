import Testing
import UZeeCore
@testable import UZeeUI

@Suite("LaunchView")
@MainActor
struct LaunchViewTests {
    @Test("Status text reflects the database state")
    func statusText() {
        let info = AppInfo(marketingVersion: "0.0.1", buildNumber: "1")
        #expect(LaunchView(info: info, status: .ready).statusText == "Database ready")
        #expect(LaunchView(info: info, status: .failed).statusText == "Database could not open")
    }
}
