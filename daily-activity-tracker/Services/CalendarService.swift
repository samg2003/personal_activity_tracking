import Foundation
import EventKit

/// Manages EventKit calendar event creation for appointment-style activities
protocol CalendarServiceProtocol {
    func requestAccess() async -> Bool
    func createEvent(title: String, date: Date, duration: TimeInterval, notes: String?) async throws -> String?
    func deleteEvent(identifier: String) throws
}

final class CalendarService: CalendarServiceProtocol {
    static let shared = CalendarService()

    private let store = EKEventStore()

    // MARK: - Access

    func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                return try await store.requestFullAccessToEvents()
            } else {
                return try await store.requestAccess(to: .event)
            }
        } catch {
            return false
        }
    }

    // MARK: - Create

    func createEvent(title: String, date: Date, duration: TimeInterval = 3600, notes: String? = nil) async throws -> String? {
        let granted = await requestAccess()
        guard granted else { return nil }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = date
        event.endDate = date.addingTimeInterval(duration)
        event.notes = notes
        event.calendar = store.defaultCalendarForNewEvents

        // Add 30-minute reminder
        event.addAlarm(EKAlarm(relativeOffset: -1800))

        try store.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    // MARK: - Delete

    func deleteEvent(identifier: String) throws {
        guard let event = store.event(withIdentifier: identifier) else { return }
        try store.remove(event, span: .thisEvent)
    }
}
