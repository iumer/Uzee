import Foundation
import UZeeCore

/// M6 bills, subscriptions, income and plan operations, injected like `LedgerClient`.
public struct RecurringClient: Sendable {
    public var snapshot: @Sendable () throws -> RecurringSnapshot
    /// Saves an item; a changed amount goes into price history from the given date.
    public var save: @Sendable (_ item: RecurringItem, _ priceFrom: LocalDate?) throws -> Void
    public var delete: @Sendable (_ item: UUID) throws -> Void
    public var setStatus: @Sendable (_ status: SubscriptionStatus, _ item: UUID) throws -> Void
    /// Posts the payment once and returns its transaction id.
    public var markPaid: @Sendable (_ item: UUID, _ scheduled: LocalDate, _ amount: Money, _ account: UUID?, _ date: Date) throws -> UUID
    public var skip: @Sendable (_ item: UUID, _ scheduled: LocalDate) throws -> Void
    public var snooze: @Sendable (_ item: UUID, _ scheduled: LocalDate, _ until: LocalDate) throws -> Void
    public var reopen: @Sendable (_ item: UUID, _ scheduled: LocalDate) throws -> Void
    public var recordPayout: @Sendable (_ payout: UUID, _ account: UUID, _ date: Date) throws -> Void

    public init(snapshot: @escaping @Sendable () throws -> RecurringSnapshot,
                save: @escaping @Sendable (RecurringItem, LocalDate?) throws -> Void,
                delete: @escaping @Sendable (UUID) throws -> Void,
                setStatus: @escaping @Sendable (SubscriptionStatus, UUID) throws -> Void,
                markPaid: @escaping @Sendable (UUID, LocalDate, Money, UUID?, Date) throws -> UUID,
                skip: @escaping @Sendable (UUID, LocalDate) throws -> Void,
                snooze: @escaping @Sendable (UUID, LocalDate, LocalDate) throws -> Void,
                reopen: @escaping @Sendable (UUID, LocalDate) throws -> Void,
                recordPayout: @escaping @Sendable (UUID, UUID, Date) throws -> Void) {
        self.snapshot = snapshot
        self.save = save
        self.delete = delete
        self.setStatus = setStatus
        self.markPaid = markPaid
        self.skip = skip
        self.snooze = snooze
        self.reopen = reopen
        self.recordPayout = recordPayout
    }

    public static let unavailable = RecurringClient(
        snapshot: { .empty }, save: { _, _ in throw CoreError.notFound }, delete: { _ in throw CoreError.notFound },
        setStatus: { _, _ in throw CoreError.notFound }, markPaid: { _, _, _, _, _ in throw CoreError.notFound },
        skip: { _, _ in throw CoreError.notFound }, snooze: { _, _, _ in throw CoreError.notFound },
        reopen: { _, _ in throw CoreError.notFound }, recordPayout: { _, _, _ in throw CoreError.notFound })
}
