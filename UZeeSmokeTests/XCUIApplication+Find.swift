import XCTest

extension XCUIApplication {
    /// The element with this identifier. In Settings, rows below the screen aren't built until scrolled to,
    /// so it scrolls down (then back up) to find them.
    func find(_ identifier: String) -> XCUIElement {
        let found = descendants(matching: .any)[identifier].firstMatch
        guard !found.exists, navigationBars["Settings"].exists else { return found }
        let list = collectionViews.firstMatch
        guard list.exists else { return found }
        for _ in 0..<6 where !found.exists { list.swipeUp() }
        for _ in 0..<6 where !found.exists { list.swipeDown() }
        return found
    }
}
