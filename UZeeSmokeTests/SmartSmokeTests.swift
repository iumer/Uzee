import XCTest

/// M9/M10 smoke tests, in-memory with sample data: typed Ask UZee questions and the lend card (VOX-004, VOX-007),
/// the statement import sheet (IMP-002 entry) and the receipt scan button (UI-034 entry).
final class SmartSmokeTests: XCTestCase {
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
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "\(identifier) missing", file: file, line: line)
        target.tap()
    }

    private func text(containing value: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }

    private func ask(_ sentence: String) {
        tap("voice.input")
        app.typeText(sentence)
        tap("voice.send")
    }

    private func openVoice() {
        app.navigationBars["Settings"].buttons.element(boundBy: 0).tap()
        tap("home.voice")
        XCTAssertTrue(element("voice.input").waitForExistence(timeout: 30), "Ask UZee did not open")
    }

    func testVOX004_subscriptionsAnswer() {
        openVoice()
        ask("How much are my subscriptions?")
        XCTAssertTrue(text(containing: "subscriptions cost").waitForExistence(timeout: 30), "No subscriptions answer")
    }

    func testVOX007_lendToFriendCard() {
        openVoice()
        ask("I lent 20k to a friend")
        XCTAssertTrue(text(containing: "Who did you lend it to?").waitForExistence(timeout: 30), "No follow-up question")
        ask("Usama")
        XCTAssertTrue(element("voice.card").waitForExistence(timeout: 30), "No confirmation card")
        tap("voiceCard.save")
        XCTAssertTrue(text(containing: "Saved").waitForExistence(timeout: 30), "Card did not save")
    }

    func testIMP002_importSheetOpens() {
        tap("settings.import")
        XCTAssertTrue(element("import.pick").waitForExistence(timeout: 30), "Import sheet missing")
        XCTAssertTrue(element("import.account").exists, "Account picker missing")
        tap("import.close")
    }

    func testUI034_scanReceiptButton() {
        app.navigationBars["Settings"].buttons.element(boundBy: 0).tap()
        tap("tab.add")
        XCTAssertTrue(element("add.scanReceipt").waitForExistence(timeout: 30), "Scan receipt missing")
        tap("add.close")
    }
}
