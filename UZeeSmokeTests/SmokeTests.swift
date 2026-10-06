import XCTest

/// Smoke tests from docs/TEST_REGISTRY.md. They never touch the real database.
final class SmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uzee-in-memory"]
        app.launch()
        return app
    }

    /// SMK-002 Application launches · SMK-003 No crash on launch
    func testSMK002_SMK003_launchesWithoutCrash() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["launch.title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// SMK-004 Database initializes
    func testSMK004_databaseInitializes() {
        let app = launchApp()
        let status = app.descendants(matching: .any)["launch.database"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Database ready")
    }

    /// ENV-006 Version display matches Info.plist
    func testENV006_versionDisplayed() {
        let app = launchApp()
        let version = app.staticTexts["launch.version"]
        XCTAssertTrue(version.waitForExistence(timeout: 10))
        // Exact values are checked in UZeeCore AppInfoTests; here the format and presence.
        XCTAssertNotNil(version.label.range(of: #"^\d+\.\d+\.\d+ \(\d+\)$"#, options: .regularExpression), "Got: \(version.label)")
    }

    /// SMK-011 Application survives relaunch
    func testSMK011_survivesRelaunch() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["launch.title"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["launch.title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)
    }
}
