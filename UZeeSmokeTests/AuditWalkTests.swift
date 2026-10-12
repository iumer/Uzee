import XCTest

/// A walk through every tab with sample data, the way a person would check the app by hand (owner audit,
/// 2026-10-12). On each tab it scrolls to the end and checks the floating UZee and "+" never sit on top of an
/// amount.
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

    /// The amount text lowest on screen, from one snapshot of the screen (querying element by element is too
    /// slow for the 3-minute test limit).
    @MainActor private func lowestAmount() -> (label: String, frame: CGRect)? {
        guard let root = try? app.snapshot() else { return nil }
        let window = root.frame
        var best: (label: String, frame: CGRect)?
        func walk(_ node: XCUIElementSnapshot) {
            if node.elementType == .staticText, node.label.contains("Rs") || node.label.contains("$"),
               window.contains(CGPoint(x: node.frame.midX, y: node.frame.midY)),
               node.frame.maxY > (best?.frame.maxY ?? -1) {
                best = (node.label, node.frame)
            }
            node.children.forEach(walk)
        }
        walk(root)
        return best
    }

    @MainActor func testAuditWalk_everyTab() {
        for name in ["Home", "Activity", "Budget", "Calendar", "People"] {
            open(name)
            XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 30), "\(name) didn't open")
            // Scroll until the screen stops moving: that is the real end of the list.
            var last = ""
            for _ in 0..<25 {
                app.swipeUp(velocity: .fast)
                let low = lowestAmount()
                let now = low.map { "\($0.label)@\(Int($0.frame.maxY))" } ?? ""
                if now == last { break }
                last = now
            }
            let voice = app.find("tab.voice"), add = app.find("tab.add")
            XCTAssertTrue(voice.exists && add.exists, "Floating UZee or + missing on \(name)")
            let floating = voice.frame.union(add.frame).insetBy(dx: -4, dy: -4)
            // At the end, the last amount must sit clear of the floating buttons.
            if let low = lowestAmount(), low.frame.intersects(floating) {
                XCTFail("On \(name), \"\(low.label)\" is under the floating UZee/+ buttons at the end of the list")
            }
        }
    }
}
