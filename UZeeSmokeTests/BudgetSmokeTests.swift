import XCTest

/// M4 smoke tests on the sample dataset, in-memory: October overview (BUD-001), the Personal over line
/// (BUD-005) and opening the limits editor (BUD-003).
final class BudgetSmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uzee-in-memory"]
        app.launch()
        tap("home.settings")
        if !element("settings.sampleOn").waitForExistence(timeout: 10), element("home.settings").exists { element("home.settings").tap() }
        tap("settings.sampleOn")
        XCTAssertTrue(element("settings.sampleOff").waitForExistence(timeout: 30))
        app.navigationBars["Settings"].buttons.element(boundBy: 0).tap()
        let tab = app.tabBars.buttons["Budget"]
        if tab.waitForExistence(timeout: 2) { tab.tap() } else { app.buttons["Budget"].firstMatch.tap() }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.find(identifier)
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "\(identifier) missing", file: file, line: line)
        target.tap()
    }

    func testBUD001_octoberOverview() {
        let spent = element("budget.spent")
        XCTAssertTrue(spent.waitForExistence(timeout: 30), "Budget overview missing")
        XCTAssertTrue(spent.label.contains("78,374") && spent.label.contains("235,000"), "Spent line was \(spent.label)")
        XCTAssertTrue(element("budget.over.Personal").exists, "Personal over line missing")
    }

    func testBUD003_openLimits() {
        tap("budget.edit")
        let total = element("limits.total")
        XCTAssertTrue(total.waitForExistence(timeout: 30), "Limits editor missing")
        XCTAssertTrue(element("limits.unassigned").label.contains("3,000"), "Unassigned was \(element("limits.unassigned").label)")
    }
}
