import XCTest

/// M3 smoke tests on the sample dataset, in-memory: day totals and search (TXN-020, TXN-025),
/// no-result state (TXN-028) and restore from Recently Deleted (DATA-010, DATA-011).
final class ActivitySmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uzee-in-memory"]
        app.launch()
        turnOnSampleData()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "\(identifier) missing", file: file, line: line)
        target.tap()
    }

    private func turnOnSampleData() {
        tap("home.settings")
        tap("settings.sampleOn")
        XCTAssertTrue(element("settings.sampleOff").waitForExistence(timeout: 10))
    }

    private func openActivity() {
        app.navigationBars["Settings"].buttons.element(boundBy: 0).tap()
        let tab = app.tabBars.buttons["Activity"]
        if tab.waitForExistence(timeout: 2) { tab.tap() } else { app.buttons["Activity"].firstMatch.tap() }
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 10))
    }

    private func search(_ text: String) {
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 3) { app.swipeDown() }
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Search field missing")
        field.tap()
        field.typeText(text)
    }

    func testTXN020_TXN025_dayTotalsAndSearch() {
        openActivity()
        let tuesday = element("day.2026-10-06")
        XCTAssertTrue(tuesday.waitForExistence(timeout: 10), "6 Oct missing")
        XCTAssertTrue(tuesday.label.contains("16,117"), "6 Oct total was \(tuesday.label)")
        search("8940")
        XCTAssertTrue(element("txn.Imtiaz Super Market").waitForExistence(timeout: 10), "Imtiaz not found by amount")
        XCTAssertFalse(element("txn.Kababjees").exists, "Search kept other rows")
    }

    func testTXN028_noResultsThenClear() {
        openActivity()
        search("zzzz")
        XCTAssertTrue(element("activity.noResults").waitForExistence(timeout: 10), "No-results state missing")
        app.buttons["Clear filters"].firstMatch.tap()
        XCTAssertTrue(element("activity.noResults").waitForNonExistence(timeout: 10))
    }

    func testDATA010_DATA011_restoreFromRecentlyDeleted() {
        tap("settings.deleted")
        XCTAssertTrue(element("deleted.Test entry").waitForExistence(timeout: 10), "Sample deleted items missing")
        XCTAssertTrue(element("deleted.Duplicate Imtiaz").exists)
        tap("deleted.Careem")
        tap("deleted.restore")
        XCTAssertTrue(element("deleted.Careem").waitForNonExistence(timeout: 10), "Careem still in Recently Deleted")
        XCTAssertTrue(element("deleted.Test entry").exists)
    }
}
