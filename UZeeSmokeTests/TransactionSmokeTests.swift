import XCTest

/// M2 transaction smoke tests (SMK-007, SMK-009, SMK-010, SMK-012) on an in-memory database.
/// SMK-008 (persists after restart) needs the on-disk database, so it is covered by the
/// UZeeData reopen test and a manual check on the owner's iPhone.
final class TransactionSmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uzee-in-memory"]
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "\(identifier) missing", file: file, line: line)
        target.tap()
    }

    private func type(_ text: String, into identifier: String, clearing: Bool = false) {
        let field = element(identifier)
        XCTAssertTrue(field.waitForExistence(timeout: 30), "\(identifier) missing")
        field.tap()
        if clearing, let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        }
        field.typeText(text)
    }

    private func balance(of account: String) -> String {
        tap("account.\(account)")
        let balance = element("account.balance")
        // A tap made while a sheet is still sliding away is dropped by iOS; try once more.
        if !balance.waitForExistence(timeout: 5) { element("account.\(account)").tap() }
        XCTAssertTrue(balance.waitForExistence(timeout: 30), "Account detail did not open")
        let label = balance.value as? String ?? balance.label
        app.navigationBars[account].buttons.element(boundBy: 0).tap()
        return label
    }

    /// Account "HBL", PKR, opening Rs 10,000, created from the Home empty state.
    private func addHBL() {
        tap("home.addAccount")
        type("HBL", into: "accountForm.name")
        type("10000", into: "accountForm.opening")
        tap("accountForm.save")
        XCTAssertTrue(element("accountForm.name").waitForNonExistence(timeout: 30), "Account form still open")
        XCTAssertTrue(element("account.HBL").waitForExistence(timeout: 30), "HBL not listed")
    }

    /// Opens "+" and saves an expense in Food › Groceries (first in the list, so no scrolling).
    private func addExpense(_ amount: String) {
        tap("tab.add")
        type(amount, into: "add.amount")
        tap("add.category")
        tap("category.Groceries")
        tap("add.save")
        tap("confirm.primary")
        XCTAssertTrue(element("add.sheet").waitForNonExistence(timeout: 30), "Add sheet still open")
    }

    /// SMK-007 Basic transaction can be created
    func testSMK007_createExpense() {
        addHBL()
        addExpense("1500")
        XCTAssertEqual(balance(of: "HBL"), "8,500 rupees")
    }

    /// SMK-009 edit, then SMK-010 delete
    func testSMK009_SMK010_editThenDelete() {
        addHBL()
        addExpense("1500")
        app.tabBars.buttons["Activity"].firstMatch.tap()
        tap("txn.Food › Groceries")
        tap("detail.edit")
        type("1650", into: "add.amount", clearing: true)
        tap("add.save")
        tap("confirm.primary")
        XCTAssertTrue(element("add.sheet").waitForNonExistence(timeout: 30))
        XCTAssertEqual(element("detail.amount").label, "1,650 rupees")
        tap("detail.delete")
        tap("detail.confirmDelete")
        app.tabBars.buttons["Home"].firstMatch.tap()
        XCTAssertEqual(balance(of: "HBL"), "10,000 rupees")
    }

    /// SMK-012 Invalid input is handled safely: refused with a message, nothing saved, input kept.
    func testSMK012_invalidInput() {
        addHBL()
        tap("tab.add")
        tap("add.save")
        XCTAssertEqual(element("add.problem").label, "Enter an amount.")
        type("0", into: "add.amount")
        tap("add.save")
        XCTAssertEqual(element("add.problem").label, "The amount must be more than zero.")
        type("5", into: "add.amount")
        tap("add.save")
        XCTAssertEqual(element("add.problem").label, "Choose a category.")
        XCTAssertEqual(element("add.amount").value as? String, "05")
        tap("add.close")
        XCTAssertEqual(balance(of: "HBL"), "10,000 rupees")
    }
}
