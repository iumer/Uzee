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

    private func tap(_ identifier: String, timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "\(identifier) missing", file: file, line: line)
        target.tap()
    }

    private func turnOnSampleData() {
        tap("home.settings")
        // On a busy Mac the first tap can land before Home is ready; tap once more.
        if !element("settings.sampleOn").waitForExistence(timeout: 10), element("home.settings").exists { element("home.settings").tap() }
        tap("settings.sampleOn")
        XCTAssertTrue(element("settings.sampleOff").waitForExistence(timeout: 30))
    }

    private func openActivity() {
        let settings = app.navigationBars["Settings"]
        settings.buttons.element(boundBy: 0).tap()
        // Wait for the pop to finish; a tab tap during the transition can be dropped.
        _ = settings.waitForNonExistence(timeout: 10)
        let activity = app.navigationBars["Activity"]
        for _ in 0..<2 where !activity.exists {
            let tab = app.tabBars.buttons["Activity"]
            if tab.waitForExistence(timeout: 2) { tab.tap() } else { app.buttons["Activity"].firstMatch.tap() }
            if activity.waitForExistence(timeout: 15) { break }
        }
        XCTAssertTrue(activity.waitForExistence(timeout: 15), "Activity didn't open")
    }

    private func search(_ text: String) {
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 3) { app.swipeDown() }
        XCTAssertTrue(field.waitForExistence(timeout: 30), "Search field missing")
        field.tap()
        field.typeText(text)
    }

    func testTXN020_TXN025_dayTotalsAndSearch() {
        openActivity()
        let tuesday = element("day.2026-10-06")
        XCTAssertTrue(tuesday.waitForExistence(timeout: 30), "6 Oct missing")
        XCTAssertTrue(tuesday.label.contains("16,117"), "6 Oct total was \(tuesday.label)")
        search("8940")
        XCTAssertTrue(element("txn.Imtiaz Super Market").waitForExistence(timeout: 30), "Imtiaz not found by amount")
        XCTAssertFalse(element("txn.Kababjees").exists, "Search kept other rows")
    }

    func testTXN028_noResultsThenClear() {
        openActivity()
        search("zzzz")
        XCTAssertTrue(element("activity.noResults").waitForExistence(timeout: 30), "No-results state missing")
        app.buttons["Clear filters"].firstMatch.tap()
        XCTAssertTrue(element("activity.noResults").waitForNonExistence(timeout: 30))
    }

    func testDATA010_DATA011_restoreFromRecentlyDeleted() {
        tap("settings.deleted")
        XCTAssertTrue(element("deleted.Test entry").waitForExistence(timeout: 30), "Sample deleted items missing")
        XCTAssertTrue(element("deleted.Duplicate Imtiaz").exists)
        tap("deleted.Careem")
        tap("deleted.restore")
        XCTAssertTrue(element("deleted.Careem").waitForNonExistence(timeout: 30), "Careem still in Recently Deleted")
        XCTAssertTrue(element("deleted.Test entry").exists)
    }
}
