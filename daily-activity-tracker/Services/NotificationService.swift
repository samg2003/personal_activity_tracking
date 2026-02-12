import Foundation
import UserNotifications

/// Handles scheduling local notifications based on ReminderPresets
protocol NotificationServiceProtocol {
    func requestPermission() async -> Bool
    func scheduleReminders(for activity: Activity) async
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

    func scheduleReminders(for activity: Activity) async {
        guard let reminder = activity.reminder else { return }

        // Clear existing for this activity
        cancelReminders(for: activity.id)

        switch reminder {
        case .morningNudge:
            await scheduleDaily(
                id: "\(activity.id)-morning",
                title: "Time for \(activity.name)",
                body: "Start your morning routine!",
                hour: 7, minute: 30
            )
        case .eveningCheckIn:
            await scheduleDaily(
                id: "\(activity.id)-evening",
                title: "Evening Check-in",
                body: "Don't forget to log \(activity.name) before bed",
                hour: 21, minute: 0
            )
        case .periodicIfBehind:
            // Schedule afternoon nudge (user can configure more granular timing later)
            await scheduleDaily(
                id: "\(activity.id)-periodic",
                title: "\(activity.name) reminder",
                body: "You haven't logged this today yet",
                hour: 14, minute: 0
            )
        case .custom:
            break // Future: custom time/interval
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
