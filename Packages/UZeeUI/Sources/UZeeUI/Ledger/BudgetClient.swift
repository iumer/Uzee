import Foundation
import UZeeCore

/// M4 budget operations, injected like `LedgerClient`.
public struct BudgetClient: Sendable {
    public var settings: @Sendable () throws -> (kind: BudgetPeriodKind, warnPercent: Int)
    public var setSettings: @Sendable (BudgetPeriodKind, Int) throws -> Void
    /// The plan for a period, copying the previous period's limits the first time (nil when never set).
    public var plan: @Sendable (BudgetPeriod) throws -> BudgetPlan?
    /// Plans that already exist, without creating any (history).
    public var existingPlans: @Sendable () throws -> [LocalDate: BudgetPlan]
    public var save: @Sendable (BudgetPlan) throws -> Void
    public var firedAlerts: @Sendable () throws -> Set<String>
    public var markFired: @Sendable ([String]) throws -> Void

    public init(settings: @escaping @Sendable () throws -> (kind: BudgetPeriodKind, warnPercent: Int),
                setSettings: @escaping @Sendable (BudgetPeriodKind, Int) throws -> Void,
                plan: @escaping @Sendable (BudgetPeriod) throws -> BudgetPlan?,
                existingPlans: @escaping @Sendable () throws -> [LocalDate: BudgetPlan],
                save: @escaping @Sendable (BudgetPlan) throws -> Void,
                firedAlerts: @escaping @Sendable () throws -> Set<String>,
                markFired: @escaping @Sendable ([String]) throws -> Void) {
        self.settings = settings
        self.setSettings = setSettings
        self.plan = plan
        self.existingPlans = existingPlans
        self.save = save
        self.firedAlerts = firedAlerts
        self.markFired = markFired
    }

    public static let unavailable = BudgetClient(
        settings: { (.calendarMonth, 80) }, setSettings: { _, _ in throw CoreError.notFound }, plan: { _ in nil },
        existingPlans: { [:] }, save: { _ in throw CoreError.notFound }, firedAlerts: { [] }, markFired: { _ in })
}
