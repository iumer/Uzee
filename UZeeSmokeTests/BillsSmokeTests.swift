import XCTest

/// M6/M7 smoke tests on the sample dataset, in-memory: the Calendar month (CAL-001), Bills & subscriptions
/// totals (REC-004) and the car plan detail (LOAN-006).
final class BillsSmokeTests: XCTestCase {
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
        let tab = app.tabBars.buttons["Calendar"]
        if tab.waitForExistence(timeout: 2) { tab.tap() } else { app.buttons["Calendar"].firstMatch.tap() }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.find(identifier)
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "\(identifier) missing", file: file, line: line)
        target.tap()
    }

    private func text(containing value: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }

    func testCAL001_monthGrid() {
        XCTAssertTrue(element("calendar.month").waitForExistence(timeout: 30), "Calendar month missing")
        XCTAssertTrue(element("calendar.day.10").exists, "Day 10 missing")
        // CAL-BUG-01: the 1st–6th used to vanish from the month grid.
        for day in 1...6 { XCTAssertTrue(element("calendar.day.\(day)").exists, "Day \(day) missing") }
        XCTAssertTrue(element("calendar.bills").exists, "Bills button missing")
    }

    func testREC004_subscriptionsTotal() {
        tap("calendar.bills")
        XCTAssertTrue(element("bills.monthly").waitForExistence(timeout: 30), "Bills summary missing")
        let subscriptions = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "14,065")).firstMatch
        if !subscriptions.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(subscriptions.waitForExistence(timeout: 10), "Rs 14,065 subscriptions line missing")
    }

    func testLOAN006_carPlan() {
        tap("calendar.bills")
        XCTAssertTrue(element("bills.monthly").waitForExistence(timeout: 30), "Bills summary missing")
        let plan = element("bills.plan.Car installment · Meezan")
        for _ in 0..<4 where !plan.isHittable { app.swipeUp() }
        plan.tap()
        let remaining = element("plan.remaining")
        XCTAssertTrue(remaining.waitForExistence(timeout: 30), "Plan detail missing")
        XCTAssertTrue(remaining.label.contains("990,000") || remaining.label.contains("945,000"), "Remaining was \(remaining.label)")
    }
}
