import SwiftUI
import UZeeCore

/// Plan (round 3 mockups N and O): Budget and Calendar in one tab behind a switch, so the bottom bar has room
/// for "+" in the middle.
struct PlanView: View {
    @Bindable var session: AppSession

    var body: some View {
        SwiftUI.Group {
            switch session.planPart {
            case .budget: BudgetView(session: session)
            case .calendar: CalendarTabView(session: session)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Show", selection: $session.planPart) {
                ForEach(PlanPart.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, UZSpacing.xxl)
            .padding(.vertical, UZSpacing.s)
            .background(UZColor.bg)
            .accessibilityIdentifier("plan.part")
        }
        .navigationTitle("Plan")
    }
}
