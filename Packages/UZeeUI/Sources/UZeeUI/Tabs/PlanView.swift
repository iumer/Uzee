import SwiftUI
import UZeeCore

/// Plan (round 3 mockups N and O): Budget and Calendar in one tab behind a switch, so the bottom bar has room
/// for "+" in the middle. Each half sets the "Plan" title and shows the switch at the top of its own scroll,
/// so the large title behaves like every other tab.
struct PlanView: View {
    @Bindable var session: AppSession

    var body: some View {
        switch session.planPart {
        case .month: MonthPlanView(session: session)
        case .budget: BudgetView(session: session)
        case .calendar: CalendarTabView(session: session)
        }
    }
}

/// Budget | Calendar, at the top of the Plan tab.
struct PlanSwitch: View {
    @Bindable var session: AppSession

    var body: some View {
        Picker("Show", selection: $session.planPart) {
            ForEach(PlanPart.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("plan.part")
    }
}
