import Foundation
import UZeeCore

/// M7 custom events, reminder preferences and the notification adapter, injected like `LedgerClient`.
public struct CalendarClient: Sendable {
    public var events: @Sendable () throws -> [CalendarEvent]
    public var saveEvent: @Sendable (CalendarEvent) throws -> Void
    public var deleteEvent: @Sendable (UUID) throws -> Void
    public var reminderSettings: @Sendable () throws -> ReminderSettings
    public var setReminderSettings: @Sendable (ReminderSettings) throws -> Void
    /// Asks for notification permission (once; later calls return the saved answer).
    public var requestNotifications: @Sendable () async -> Bool
    public var notificationsAllowed: @Sendable () async -> Bool
    /// Replaces UZee's pending reminders with this plan.
    public var schedule: @Sendable ([PlannedReminder]) async -> Void
    /// Apple Calendar export (CAL-06): permission, the calendars UZee may write to, and syncing its own events.
    public var requestCalendarAccess: @Sendable () async -> Bool
    public var calendars: @Sendable () -> [CalendarChoice]
    public var defaultCalendarID: @Sendable () -> String?
    public var exportToCalendar: @Sendable ([CalendarExportItem], String?, LocalDate) async -> Void
    /// Plan › To pay (owner, 2026-10-15).
    public var paymentTodos: @Sendable () throws -> [PaymentTodo]
    public var savePaymentTodo: @Sendable (PaymentTodo) throws -> Void
    public var deletePaymentTodo: @Sendable (UUID) throws -> Void
    /// Each payment on a to-do, with its date and the entry it made (owner, 2026-11-03).
    public var payments: TodoPaymentsClient = .unavailable

    public init(events: @escaping @Sendable () throws -> [CalendarEvent],
                saveEvent: @escaping @Sendable (CalendarEvent) throws -> Void,
                deleteEvent: @escaping @Sendable (UUID) throws -> Void,
                reminderSettings: @escaping @Sendable () throws -> ReminderSettings,
                setReminderSettings: @escaping @Sendable (ReminderSettings) throws -> Void,
                requestNotifications: @escaping @Sendable () async -> Bool,
                notificationsAllowed: @escaping @Sendable () async -> Bool,
                schedule: @escaping @Sendable ([PlannedReminder]) async -> Void,
                requestCalendarAccess: @escaping @Sendable () async -> Bool = { false },
                calendars: @escaping @Sendable () -> [CalendarChoice] = { [] },
                defaultCalendarID: @escaping @Sendable () -> String? = { nil },
                exportToCalendar: @escaping @Sendable ([CalendarExportItem], String?, LocalDate) async -> Void = { _, _, _ in },
                paymentTodos: @escaping @Sendable () throws -> [PaymentTodo] = { [] },
                savePaymentTodo: @escaping @Sendable (PaymentTodo) throws -> Void = { _ in throw CoreError.notFound },
                deletePaymentTodo: @escaping @Sendable (UUID) throws -> Void = { _ in throw CoreError.notFound }) {
        self.events = events
        self.saveEvent = saveEvent
        self.deleteEvent = deleteEvent
        self.reminderSettings = reminderSettings
        self.setReminderSettings = setReminderSettings
        self.requestNotifications = requestNotifications
        self.notificationsAllowed = notificationsAllowed
        self.schedule = schedule
        self.requestCalendarAccess = requestCalendarAccess
        self.calendars = calendars
        self.defaultCalendarID = defaultCalendarID
        self.exportToCalendar = exportToCalendar
        self.paymentTodos = paymentTodos
        self.savePaymentTodo = savePaymentTodo
        self.deletePaymentTodo = deletePaymentTodo
    }

    public static let unavailable = CalendarClient(
        events: { [] }, saveEvent: { _ in throw CoreError.notFound }, deleteEvent: { _ in throw CoreError.notFound },
        reminderSettings: { .standard }, setReminderSettings: { _ in throw CoreError.notFound },
        requestNotifications: { false }, notificationsAllowed: { false }, schedule: { _ in })
}

/// The payment history of a To pay / To receive item.
public struct TodoPaymentsClient: Sendable {
    public var list: @Sendable (UUID) throws -> [TodoPayment]
    public var add: @Sendable (TodoPayment) throws -> Void
    public var update: @Sendable (TodoPayment) throws -> Void
    public var delete: @Sendable (UUID) throws -> Void
    public var restore: @Sendable (UUID) throws -> Void
    public var clear: @Sendable (UUID) throws -> Void
    /// An earlier payment and the one Activity entry that looks like it: (payment, transaction, its amount).
    public var suggestedLink: @Sendable (UUID) throws -> (UUID, UUID, Money)?
    public var link: @Sendable (UUID, UUID) throws -> Void

    public init(list: @escaping @Sendable (UUID) throws -> [TodoPayment], add: @escaping @Sendable (TodoPayment) throws -> Void,
                update: @escaping @Sendable (TodoPayment) throws -> Void, delete: @escaping @Sendable (UUID) throws -> Void,
                restore: @escaping @Sendable (UUID) throws -> Void, clear: @escaping @Sendable (UUID) throws -> Void,
                suggestedLink: @escaping @Sendable (UUID) throws -> (UUID, UUID, Money)?, link: @escaping @Sendable (UUID, UUID) throws -> Void) {
        self.list = list
        self.add = add
        self.update = update
        self.delete = delete
        self.restore = restore
        self.clear = clear
        self.suggestedLink = suggestedLink
        self.link = link
    }

    public static let unavailable = TodoPaymentsClient(
        list: { _ in [] }, add: { _ in throw CoreError.notFound }, update: { _ in throw CoreError.notFound },
        delete: { _ in throw CoreError.notFound }, restore: { _ in throw CoreError.notFound }, clear: { _ in throw CoreError.notFound },
        suggestedLink: { _ in nil }, link: { _, _ in throw CoreError.notFound })
}
