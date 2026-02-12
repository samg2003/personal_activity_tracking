import Foundation
import UserNotifications

/// Handles scheduling local notifications based on ReminderPresets
protocol NotificationServiceProtocol {
    func requestPermission() async -> Bool
    func scheduleReminders(id: UUID, name: String, reminder: ReminderPreset) async
    func cancelReminders(for activityID: UUID)
    func scheduleEveningCheckIn(pendingCount: Int) async
}

final class NotificationService: NotificationServiceProtocol {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - Schedule

    func scheduleReminders(id: UUID, name: String, reminder: ReminderPreset) async {
        cancelReminders(for: id)

        switch reminder {
        case .morningNudge:
            await scheduleDaily(
                id: "\(id)-morning",
                title: "Time for \(name)",
                body: "Start your morning routine!",
                hour: 8, minute: 0
            )
        case .eveningCheckIn:
            await scheduleDaily(
                id: "\(id)-evening",
                title: "Evening Check-in",
                body: "Don't forget to log \(name) before bed",
                hour: 20, minute: 0
            )
        case .periodic(let hours):
            await scheduleDaily(
                id: "\(id)-periodic",
                title: "\(name) reminder",
                body: "You haven't logged this today yet",
                hour: min(8 + hours, 20), minute: 0
            )
        case .remindAt(let hour, let minute):
            await scheduleDaily(
                id: "\(id)-custom",
                title: "\(name)",
                body: "Time to log \(name)",
                hour: hour, minute: minute
            )
        case .none:
            break
        }
    }

    func cancelReminders(for activityID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [
            "\(activityID)-morning",
            "\(activityID)-evening",
            "\(activityID)-periodic",
        ])
    }

    // MARK: - Evening summary

    func scheduleEveningCheckIn(pendingCount: Int) async {
        guard pendingCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "You have \(pendingCount) activities left"
        content.body = "Finish strong today! 💪"
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = 20
        dateComponents.minute = 30

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: "evening-summary", content: content, trigger: trigger)

        try? await center.add(request)
    }

    // MARK: - Private

    private func scheduleDaily(id: String, title: String, body: String, hour: Int, minute: Int) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        try? await center.add(request)
    }
}
