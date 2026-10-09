import XCTest

/// The owner's requests and bug reports that a screen test can check (docs/OWNER_CHECKLIST.md). These run on
/// every build so a new fix can't quietly undo an old one. In-memory, with sample data.
final class OwnerRequestSmokeTests: XCTestCase {
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
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.find(identifier)
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "\(identifier) missing", file: file, line: line)
        target.tap()
    }

    private func backToHome() {
        app.navigationBars["Settings"].buttons.element(boundBy: 0).tap()
    }

    /// OWN-006: Ask UZee opens for talking, with no text box until you choose to type.
    func testOWN006_voiceOpensWithoutTextBox() {
        backToHome()
        tap("home.voice")
        XCTAssertTrue(element("voice.keyboard").waitForExistence(timeout: 30), "Keyboard switch missing")
        XCTAssertFalse(element("voice.input").exists, "The text box shows before choosing to type")
        tap("voice.keyboard")
        XCTAssertTrue(element("voice.input").waitForExistence(timeout: 30), "Typing didn't open")
    }

    /// OWN-009 and OWN-011: Settings keeps UZee's voice, erase everything and the Wise rate.
    func testOWN009_OWN011_settingsRows() {
        // Setup scrolled down to the sample-data row; go back to the top so Exchange rate is fully on screen.
        let list = app.collectionViews.firstMatch
        for _ in 0..<4 where list.exists { list.swipeDown() }
        tap("settings.rate")
        XCTAssertTrue(element("rate.wise").waitForExistence(timeout: 30), "Live rate from Wise missing")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("settings.uzeeVoice").waitForExistence(timeout: 30), "UZee's voice missing")
        XCTAssertTrue(element("settings.erase").waitForExistence(timeout: 30), "Erase everything missing")
    }

    /// OWN-004: from a person you can record "they paid you" (part of what they owe).
    func testOWN004_personRepayment() {
        backToHome()
        let tab = app.tabBars.buttons["People"]
        if tab.waitForExistence(timeout: 2) { tab.tap() } else { app.buttons["People"].firstMatch.tap() }
        tap("person.Usama")
        let balance = element("person.balance")
        if !balance.waitForExistence(timeout: 5) { element("person.Usama").coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap() }
        XCTAssertTrue(balance.waitForExistence(timeout: 30), "Usama did not open")
        XCTAssertTrue(element("person.repay").waitForExistence(timeout: 30), "They paid you missing")
    }
}
