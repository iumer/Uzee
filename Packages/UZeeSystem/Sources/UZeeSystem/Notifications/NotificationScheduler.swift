import Foundation
import UserNotifications
import UZeeCore

/// Local notifications for bills, events and loans (CAL-04/05). Planning is pure (UZeeCore ReminderPlanner);
/// this adapter replaces UZee's pending requests with the plan and handles Mark paid, Snooze and Open.
public final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = NotificationScheduler()

    public static let billCategory = "uzee.bill"
    public static let markPaidAction = "uzee.markPaid"
    public static let snoozeAction = "uzee.snooze"

    /// What a tapped action asks the app to do.
    public enum Response: Sendable {
        case markPaid(item: UUID, scheduled: LocalDate)
        case snooze(item: UUID, scheduled: LocalDate)
        case open(item: UUID?, date: LocalDate?)
    }

    private let center = UNUserNotificationCenter.current()
    private var handler: (@Sendable (Response) async -> Void)?

    /// Becomes the notification delegate and registers the bill actions. Call once at launch.
    public func start(handler: @escaping @Sendable (Response) async -> Void) {
        self.handler = handler
        center.delegate = self
        let markPaid = UNNotificationAction(identifier: Self.markPaidAction, title: "Mark paid",
                                            options: [.authenticationRequired, .foreground], icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"))
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze 1 day", options: [],
                                          icon: UNNotificationActionIcon(systemImageName: "clock.arrow.circlepath"))
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.billCategory, actions: [markPaid, snooze],
                                                                 intentIdentifiers: [], options: [])])
    }

    /// Asks once; later calls return the saved answer without a prompt.
    public func requestAccess() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    public func isAllowed() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Replaces every pending UZee reminder with `plan`, at local wall-clock times (they follow time-zone changes).
    public func schedule(_ plan: [PlannedReminder]) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(PlannedReminder.idPrefix) }
        let wanted = Set(plan.map(\.id))
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { !wanted.contains($0) })
        guard await isAllowed() else { return }
        for reminder in plan {
            // A newer plan has taken over.
            if Task.isCancelled { return }
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.threadIdentifier = reminder.kind.rawValue
            var info: [String: String] = ["kind": reminder.kind.rawValue]
            if let item = reminder.itemID { info["item"] = item.uuidString }
            if let date = reminder.scheduledDate { info["date"] = date.description }
            content.userInfo = info
            if reminder.kind == .bill { content.categoryIdentifier = Self.billCategory }
            var when = DateComponents()
            when.year = reminder.fireDate.year
            when.month = reminder.fireDate.month
            when.day = reminder.fireDate.day
            when.hour = reminder.minuteOfDay / 60
            when.minute = reminder.minuteOfDay % 60
            let request = UNNotificationRequest(identifier: reminder.id, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
            try? await center.add(request)
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let item = (info["item"] as? String).flatMap(UUID.init(uuidString:))
        let date = (info["date"] as? String).flatMap(LocalDate.init)
        let kind = info["kind"] as? String
        let action: Response
        switch response.actionIdentifier {
        case Self.markPaidAction where item != nil && date != nil && kind == PlannedReminder.Kind.bill.rawValue:
            action = .markPaid(item: item!, scheduled: date!)
        case Self.snoozeAction where item != nil && date != nil && kind == PlannedReminder.Kind.bill.rawValue:
            action = .snooze(item: item!, scheduled: date!)
        default:
            action = kind == PlannedReminder.Kind.prayer.rawValue ? .open(item: nil, date: nil)
                : .open(item: kind == PlannedReminder.Kind.bill.rawValue ? item : nil, date: date)
        }
        await handler?(action)
    }
}
