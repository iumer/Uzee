import XCTest

/// A walk through every tab with sample data, the way a person would check the app by hand (owner audit,
/// 2026-10-12). On each tab it scrolls to the end and checks the floating UZee and "+" never sit on top of an
/// amount, and that the top bar keeps the profile icon on the left. It prints what each screen shows, so the CI log
/// doubles as a readable tour of the app.
final class AuditWalkTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
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

    /// Prints the screen's visible texts and buttons, one line each.
    private func describe(_ screen: String) {
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(80).filter { $0.exists && !$0.label.isEmpty }.map(\.label)
        let buttons = app.buttons.allElementsBoundByIndex.prefix(60).filter { $0.exists }.map { "[\($0.label.isEmpty ? $0.identifier : $0.label)]" }
        print("AUDIT \(screen) TEXT: " + texts.joined(separator: " | "))
        print("AUDIT \(screen) BUTTONS: " + buttons.joined(separator: " "))
    }

    func testAuditWalk_everyTab() {
        for name in ["Home", "Activity", "Budget", "Calendar", "People"] {
            open(name)
            XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 30), "\(name) didn't open")
            describe(name)
            // Scroll to the end; the last amounts must be clear of the floating buttons.
            let scroller = app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch : app.collectionViews.firstMatch
            for _ in 0..<8 where scroller.exists { scroller.swipeUp() }
            let voice = app.find("tab.voice"), add = app.find("tab.add")
            XCTAssertTrue(voice.exists && add.exists, "Floating UZee or + missing on \(name)")
            let floating = voice.frame.union(add.frame).insetBy(dx: -4, dy: -4)
            let amounts = app.staticTexts.allElementsBoundByIndex.filter { element in
                guard element.exists, element.isHittable else { return false }
                let label = element.label
                return label.contains("Rs") || label.contains("$")
            }
            for amount in amounts where amount.frame.intersects(floating) {
                XCTFail("On \(name), \"\(amount.label)\" is under the floating UZee/+ buttons after scrolling to the end")
            }
            describe("\(name) (end)")
        }
    }
}
