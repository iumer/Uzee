import Foundation
import Testing
import UZeeCore
@testable import UZeeUI

/// UI-005, UI-006, UI-007 (component logic). Rendering is checked by the smoke UI tests and screenshots.
@Suite("Design system")
@MainActor
struct DesignSystemTests {
    @Test("UI-005 AmountText shows native amount with ≈ Rs line")
    func amountText() {
        let wise = AmountText(Money(minorUnits: 52_000, currency: .usd))
        #expect(wise.primaryText == "$520.00")
        #expect(wise.secondaryText == "≈ Rs 145,600")
        #expect(wise.spokenText == "520 US dollars, about 145,600 rupees")

        let hbl = AmountText(Money(major: 182_400, .pkr))
        #expect(hbl.primaryText == "Rs 182,400")
        #expect(hbl.secondaryText == nil)

        #expect(AmountText(Money(major: 1_600, .pkr), style: .outflow).primaryText == "\u{2212}Rs 1,600")
        #expect(AmountText(Money(major: 1_600, .pkr), style: .outflow).spokenText == "minus 1,600 rupees")
        #expect(AmountText(Money(minorUnits: 187_500, currency: .usd), style: .inflow).primaryText == "+$1,875.00")
    }

    @Test("UI-006 status is always words plus a symbol")
    func statusWords() {
        #expect(StatusBadge.Status.owesYou.text == "owes you")
        #expect(StatusBadge.Status.youOwe.text == "you owe")
        #expect(StatusBadge.Status.paid.text == "Paid")
        #expect(StatusBadge.Status.overdue.text == "Overdue")
        for status in StatusBadge.Status.allCases {
            #expect(!status.text.isEmpty)
            #expect(!status.symbol.isEmpty)
        }
    }

    @Test("UI-007 fixed category colours")
    func categoryColours() {
        #expect(CategoryStyle.lightHex(.office) == 0x5856D6)
        #expect(CategoryStyle.lightHex(.transport) == 0x007AFF)
        #expect(CategoryStyle.lightHex(.food) == 0xFF9500)
        #expect(CategoryStyle.lightHex(.personal) == 0x30B0C7)
        #expect(CategoryStyle.lightHex(.utilities) == 0xFFCC00)
        #expect(CategoryStyle.lightHex(.subscriptions) == 0xFF2D55)
        #expect(CategoryStyle.lightHex(.financial) == 0x00C7BE)
        #expect(CategoryStyle.lightHex(.health) == 0xFF3B30)
        #expect(CategoryStyle.lightHex(.income) == 0x34C759)
    }

    @Test("Progress levels switch at the warning threshold and over 100 %")
    func progressLevels() {
        #expect(ProgressLevel(fraction: 0.5) == .under)
        #expect(ProgressLevel(fraction: 0.85) == .near)
        #expect(ProgressLevel(fraction: 1.0) == .near)
        #expect(ProgressLevel(fraction: 1.14) == .over)
    }
}

@Suite("App session")
@MainActor
struct AppSessionTests {
    final class FakeStore: @unchecked Sendable {
        var active = false
        var removed = 0
        var failRemove = false
    }

    func makeSession(_ store: FakeStore) -> AppSession {
        AppSession(
            info: AppInfo(marketingVersion: "0.1.0", buildNumber: "2"),
            isDatabaseReady: true,
            sampleData: .init(
                isActive: { store.active },
                load: { store.active = true },
                removeAll: {
                    if store.failRemove { throw CoreError.notFound }
                    store.active = false
                    store.removed += 1
                    return 3
                }
            )
        )
    }

    @Test("UI-003 choosing + opens Add and keeps the current tab")
    func addKeepsTab() {
        let session = makeSession(FakeStore())
        session.tabSelection.wrappedValue = .budget
        session.tabSelection.wrappedValue = .add
        #expect(session.selectedTab == .budget)
        #expect(session.isAddPresented)
    }

    @Test("UI-002 each tab keeps its own navigation path")
    func pathsPerTab() {
        let session = makeSession(FakeStore())
        session.path(for: .home).wrappedValue = [.settings]
        session.tabSelection.wrappedValue = .budget
        session.tabSelection.wrappedValue = .home
        #expect(session.path(for: .home).wrappedValue == [.settings])
        #expect(session.path(for: .budget).wrappedValue.isEmpty)
    }

    @Test("UI-001 tab order")
    func tabOrder() {
        #expect(AppTab.screens.map(\.title) == ["Home", "Activity", "Budget", "Calendar", "People"])
    }

    @Test("DATA-001 sample mode on and off")
    func sampleMode() {
        let store = FakeStore()
        let session = makeSession(store)
        #expect(!session.isSampleMode)
        session.turnOnSampleData()
        #expect(session.isSampleMode)
        session.removeSampleData()
        #expect(!session.isSampleMode)
        #expect(store.removed == 1)
    }

    @Test("A failed removal keeps sample mode and explains")
    func sampleRemoveFails() {
        let store = FakeStore()
        store.active = true
        store.failRemove = true
        let session = makeSession(store)
        session.removeSampleData()
        #expect(session.isSampleMode)
        #expect(session.errorMessage?.contains("Nothing was changed") == true)
    }

    @Test("UI-009 toast offers Undo and runs it once")
    func toastUndo() {
        let toasts = ToastCenter()
        var undone = 0
        toasts.show("Saved") { undone += 1 }
        #expect(toasts.current?.message == "Saved")
        #expect(toasts.current?.hasUndo == true)
        toasts.performUndo()
        toasts.performUndo()
        #expect(undone == 1)
        #expect(toasts.current?.message == "Undone")
        toasts.dismiss()
        #expect(toasts.current == nil)
    }
}
