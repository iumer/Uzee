import EventKit
import Foundation
import UZeeCore

/// Writes UZee's bills, events and loan dates to a calendar the owner picks (CAL-06). UZee remembers which
/// events it made and only ever changes or removes those; the owner's own events are never touched.
public final class CalendarExporter: @unchecked Sendable {
    public static let shared = CalendarExporter()

    private let store = EKEventStore()
    private let lock = NSLock()
    /// key → [event id, date]; kept on this iPhone only.
    private static let mappingKey = "uzee.calendarExport.events"

    public init() {}

    public var isAllowed: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    public func requestAccess() async -> Bool {
        if isAllowed { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Calendars UZee may write to.
    public func calendars() -> [CalendarChoice] {
        guard isAllowed else { return [] }
        return store.calendars(for: .event).filter(\.allowsContentModifications)
            .map { CalendarChoice(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title) }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }

    public var defaultCalendarID: String? { isAllowed ? store.defaultCalendarForNewEvents?.calendarIdentifier : nil }

    /// Brings the calendar in line with `items`. With `calendarID` nil, removes every future event UZee made.
    public func sync(_ items: [CalendarExportItem], calendarID: String?, today: LocalDate) {
        lock.lock()
        defer { lock.unlock() }
        guard isAllowed else { return }
        var mapping = Self.loadMapping()
        let calendar = calendarID.flatMap { store.calendar(withIdentifier: $0) }
        // A calendar the owner deleted, or export turned off: start over.
        let wanted = calendar == nil ? [] : items
        // An event the owner deleted in Calendar is made again only if it is still wanted.
        let existing = mapping.compactMapValues { $0.first }.filter { store.event(withIdentifier: $0.value) != nil }
        let dates = mapping.compactMapValues { $0.last.flatMap { LocalDate($0) } }
        let changes = CalendarExportPlanner.changes(wanted: wanted, existing: existing, existingDates: dates, today: today)

        for id in changes.delete {
            if let event = store.event(withIdentifier: id) { try? store.remove(event, span: .thisEvent, commit: false) }
            mapping = mapping.filter { $0.value.first != id }
        }
        // Gone from Calendar and no longer wanted: forget it.
        for key in mapping.keys where existing[key] == nil && !wanted.contains(where: { $0.key == key }) { mapping[key] = nil }
        if let calendar {
            for (id, item) in changes.update {
                guard let event = store.event(withIdentifier: id) else { continue }
                fill(event, with: item)
                if event.calendar.calendarIdentifier != calendar.calendarIdentifier { event.calendar = calendar }
                if event.hasChanges { try? store.save(event, span: .thisEvent, commit: false) }
                mapping[item.key] = [id, item.date.description]
            }
            for item in changes.create {
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                fill(event, with: item)
                // Committed one by one: a new event has its identifier only once it is saved.
                guard (try? store.save(event, span: .thisEvent, commit: true)) != nil,
                      let id = event.eventIdentifier as String? else { continue }
                mapping[item.key] = [id, item.date.description]
            }
        }
        try? store.commit()
        Self.saveMapping(mapping)
    }

    private func fill(_ event: EKEvent, with item: CalendarExportItem) {
        let start = item.date.startDate(in: .current)
        if event.title != item.title { event.title = item.title }
        if event.notes != item.notes { event.notes = item.notes }
        if let minute = item.minuteOfDay {
            let begins = start.addingTimeInterval(TimeInterval(minute * 60))
            if event.isAllDay { event.isAllDay = false }
            if event.startDate != begins { event.startDate = begins; event.endDate = begins.addingTimeInterval(30 * 60) }
        } else {
            if !event.isAllDay { event.isAllDay = true }
            if event.startDate != start { event.startDate = start; event.endDate = start }
        }
    }

    private static func loadMapping() -> [String: [String]] {
        (UserDefaults.standard.dictionary(forKey: mappingKey) as? [String: [String]]) ?? [:]
    }

    private static func saveMapping(_ mapping: [String: [String]]) {
        UserDefaults.standard.set(mapping, forKey: mappingKey)
    }
}
