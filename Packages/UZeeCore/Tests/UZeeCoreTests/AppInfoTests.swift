import Testing
@testable import UZeeCore

@Suite("AppInfo")
struct AppInfoTests {
    // ENV-006 (logic part): version text matches Info.plist values.
    @Test("Display version combines marketing version and build")
    func displayVersion() {
        let info = AppInfo(infoDictionary: ["CFBundleShortVersionString": "0.0.1", "CFBundleVersion": "1"])
        #expect(info.displayVersion == "0.0.1 (1)")
    }

    @Test("Missing Info.plist values fall back safely")
    func missingValues() {
        let info = AppInfo(infoDictionary: nil)
        #expect(info.displayVersion == "0.0.0 (0)")
    }
}
