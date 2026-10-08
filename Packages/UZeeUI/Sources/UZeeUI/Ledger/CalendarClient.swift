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
                exportToCalendar: @escaping @Sendable ([CalendarExportItem], String?, LocalDate) async -> Void = { _, _, _ in }) {
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
    }

    public static let unavailable = CalendarClient(
        events: { [] }, saveEvent: { _ in throw CoreError.notFound }, deleteEvent: { _ in throw CoreError.notFound },
        reminderSettings: { .standard }, setReminderSettings: { _ in throw CoreError.notFound },
        requestNotifications: { false }, notificationsAllowed: { false }, schedule: { _ in })
}
