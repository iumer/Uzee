import XCTest

/// Smoke and M1 navigation tests from docs/TEST_REGISTRY.md. They never touch the real database.
/// Written to run on iPhone (tab bar) and iPad (sidebar-adaptable tab bar).
final class SmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private let tabs = ["Home", "Activity", "Budget", "Calendar", "People"]

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uzee-in-memory"]
        app.launch()
    }

    // MARK: Helpers

    private func tapTab(_ name: String) {
        let tabBarButton = app.tabBars.buttons[name]
        if tabBarButton.waitForExistence(timeout: 2) {
            tabBarButton.tap()
        } else {
            app.buttons[name].firstMatch.tap()
        }
    }

    @discardableResult
    private func expectScreen(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let bar = app.navigationBars[title]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "Screen \(title) not shown", file: file, line: line)
        return bar
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func openSettings() {
        element("home.settings").tap()
        expectScreen("Settings")
    }

    private func goBack(from title: String) {
        app.navigationBars[title].buttons.element(boundBy: 0).tap()
    }

    // MARK: Smoke

    /// SMK-002 Application launches · SMK-003 No crash on launch
    func testSMK002_SMK003_launchesWithoutCrash() {
        expectScreen("Home")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// SMK-004 Database initializes
    func testSMK004_databaseInitializes() {
        openSettings()
        let status = element("settings.database")
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Database ready")
    }

    /// ENV-006 Version display matches Info.plist
    func testENV006_versionDisplayed() {
        openSettings()
        let version = element("settings.version")
        XCTAssertTrue(version.waitForExistence(timeout: 10))
        XCTAssertNotNil(version.label.range(of: #"^Version \d+\.\d+\.\d+ \(\d+\)$"#, options: .regularExpression), "Got: \(version.label)")
    }

    /// SMK-011 Application survives relaunch
    func testSMK011_survivesRelaunch() {
        expectScreen("Home")
        app.terminate()
        app.launch()
        expectScreen("Home")
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: M1 navigation

    /// SMK-005 Main navigation loads · UI-001 Tab order
    func testSMK005_UI001_tabsInOrderAndOpen() {
        if app.tabBars.firstMatch.waitForExistence(timeout: 5) {
            let labels = app.tabBars.firstMatch.buttons.allElementsBoundByIndex.map(\.label)
            XCTAssertEqual(Array(labels.prefix(5)), tabs, "Tab order")
        }
        for tab in tabs {
            tapTab(tab)
            expectScreen(tab)
        }
    }

    /// UI-003 "+" opens Add from every tab; Close returns to the same tab
    func testUI003_addFromEveryTab() {
        for tab in tabs {
            tapTab(tab)
            expectScreen(tab)
            tapTab("Add")
            let close = element("add.close")
            XCTAssertTrue(close.waitForExistence(timeout: 5), "Add sheet not shown from \(tab)")
            close.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 5))
            expectScreen(tab)
        }
    }

    /// UI-002 Each tab keeps its navigation state
    func testUI002_tabKeepsNavigationState() {
        openSettings()
        tapTab("Budget")
        expectScreen("Budget")
        tapTab("Home")
        expectScreen("Settings")
    }

    /// UI-012 Home toolbar: mic opens Ask UZee, gear opens Settings
    func testUI012_homeToolbar() {
        element("home.voice").tap()
        let close = element("voice.close")
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        openSettings()
    }

    /// DATA-001 Sample banner on every tab while sample mode is on; one action removes it
    func testDATA001_sampleBannerOnEveryTab() {
        openSettings()
        element("settings.sampleOn").tap()
        XCTAssertTrue(element("settings.sampleOff").waitForExistence(timeout: 5))
        goBack(from: "Settings")
        for tab in tabs {
            tapTab(tab)
            expectScreen(tab)
            XCTAssertTrue(element("sample.banner").waitForExistence(timeout: 5), "No banner on \(tab)")
        }
        element("sample.remove").tap()
        let confirm = app.buttons["Remove sample data"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(element("sample.banner").waitForNonExistence(timeout: 5))
    }
}
