import XCTest

/// M5 smoke tests on the sample dataset, in-memory: overall balances (SPL-015), a person's balance
/// (LOAN-001) and the Office group (SPL-010, SPL-012).
final class PeopleSmokeTests: XCTestCase {
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
        let tab = app.tabBars.buttons["People"]
        if tab.waitForExistence(timeout: 2) { tab.tap() } else { app.buttons["People"].firstMatch.tap() }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "\(identifier) missing", file: file, line: line)
        target.tap()
    }

    func testSPL015_overallAndPerson() {
        let owed = element("people.owed")
        XCTAssertTrue(owed.waitForExistence(timeout: 30), "People summary missing")
        XCTAssertTrue(owed.label.contains("35,000"), "Owed to you was \(owed.label)")
        XCTAssertTrue(element("people.owe").label.contains("88,000"), "You owe was \(element("people.owe").label)")
        tap("person.Usama")
        let balance = element("person.balance")
        // Plain-style links in cards sometimes miss a synthesized tap; tap the row's centre once more.
        if !balance.waitForExistence(timeout: 5) { element("person.Usama").coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap() }
        XCTAssertTrue(balance.waitForExistence(timeout: 30), "Usama did not open")
        XCTAssertTrue(balance.label.contains("25,000"), "Usama balance was \(balance.label)")
    }

    func testSPL010_officeGroup() {
        tap("people.groups")
        tap("group.Office")
        let partner = element("groupBalance.Office partner")
        XCTAssertTrue(partner.waitForExistence(timeout: 30), "Office balance missing")
        XCTAssertTrue(partner.label.contains("9,800"), "Office partner was \(partner.label)")
    }
}
