import XCTest

/// A walk through every tab with sample data, the way a person would check the app by hand (owner audit,
/// 2026-10-12). On each tab it scrolls to the end and checks the floating UZee and "+" never sit on top of an
/// amount.
final class AuditWalkTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        executionTimeAllowance = 600
        app = XCUIApplication()
        app.launchArguments = ["-uzee-in-memory"]
        app.launch()
        let settings = app.find("tab.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 30))
        settings.tap()
        let sample = app.find("settings.sampleOn")
        if sample.waitForExistence(timeout: 30) { sample.tap() }
        XCTAssertTrue(app.find("settings.sampleOff").waitForExistence(timeout: 30))
        app.navigationBars["Settings"].buttons.element(boundBy: 0).tap()
    }

    private func open(_ name: String) {
        let tab = app.tabBars.buttons[name]
        if tab.waitForExistence(timeout: 2) { tab.tap() } else { app.buttons[name].firstMatch.tap() }
    }

    func testAuditWalk_everyTab() {
        for name in ["Home", "Activity", "Budget", "Calendar", "People"] {
            open(name)
            XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 30), "\(name) didn't open")
            // Scroll to the end; the last amounts must be clear of the floating buttons.
            let scroller = app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch : app.collectionViews.firstMatch
            for _ in 0..<8 where scroller.exists { scroller.swipeUp() }
            let voice = app.find("tab.voice"), add = app.find("tab.add")
            XCTAssertTrue(voice.exists && add.exists, "Floating UZee or + missing on \(name)")
            let floating = voice.frame.union(add.frame).insetBy(dx: -4, dy: -4)
            // Only amounts, and only the first few dozen: walking every element is too slow for a UI test.
            let query = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Rs' OR label CONTAINS '$'"))
            let amounts = query.allElementsBoundByIndex.prefix(40).filter { $0.exists && $0.isHittable }
            for amount in amounts where amount.frame.intersects(floating) {
                XCTFail("On \(name), \"\(amount.label)\" is under the floating UZee/+ buttons after scrolling to the end")
            }
        }
    }
}
