import XCTest

extension XCUIApplication {
    /// The element with this identifier. In Settings, rows below the screen aren't built until scrolled to,
    /// so it scrolls down (then back up) to find them. Only Settings rows ("settings.…") are scrolled to: swiping
    /// down on a sheet that is still opening would close it.
    func find(_ identifier: String) -> XCUIElement {
        let found = descendants(matching: .any)[identifier].firstMatch
        guard identifier.hasPrefix("settings."), !found.waitForExistence(timeout: 2), navigationBars["Settings"].exists else { return found }
        let list = collectionViews.firstMatch
        guard list.exists else { return found }
        for _ in 0..<6 where !found.exists { list.swipeUp() }
        for _ in 0..<6 where !found.exists { list.swipeDown() }
        return found
    }
}
