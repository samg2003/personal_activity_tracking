import Foundation
import UserNotifications

/// Global day-part notification reminders (morning, afternoon, evening).
/// Configuration stored in UserDefaults; no per-activity reminders.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    // MARK: - UserDefaults Keys

    private enum Key {
        static let morningEnabled = "notif_morning_enabled"
        static let morningHour = "notif_morning_hour"
        static let morningMinute = "notif_morning_minute"

        static let afternoonEnabled = "notif_afternoon_enabled"
        static let afternoonHour = "notif_afternoon_hour"
        static let afternoonMinute = "notif_afternoon_minute"

        static let eveningEnabled = "notif_evening_enabled"
        static let eveningHour = "notif_evening_hour"
        static let eveningMinute = "notif_evening_minute"
    }

    // MARK: - Notification IDs

    private enum ID {
        static let morning = "global-morning"
        static let afternoon = "global-afternoon"
        static let evening = "global-evening"
    }

    // MARK: - Config Accessors

    struct DayPartConfig {
        var enabled: Bool
        var hour: Int
        var minute: Int
    }

    var morningConfig: DayPartConfig {
        get {
            DayPartConfig(
                enabled: UserDefaults.standard.bool(forKey: Key.morningEnabled),
                hour: UserDefaults.standard.object(forKey: Key.morningHour) as? Int ?? 8,
                minute: UserDefaults.standard.object(forKey: Key.morningMinute) as? Int ?? 0
            )
        }
        set {
            UserDefaults.standard.set(newValue.enabled, forKey: Key.morningEnabled)
            UserDefaults.standard.set(newValue.hour, forKey: Key.morningHour)
            UserDefaults.standard.set(newValue.minute, forKey: Key.morningMinute)
        }
    }

    var afternoonConfig: DayPartConfig {
        get {
            DayPartConfig(
                enabled: UserDefaults.standard.bool(forKey: Key.afternoonEnabled),
                hour: UserDefaults.standard.object(forKey: Key.afternoonHour) as? Int ?? 13,
                minute: UserDefaults.standard.object(forKey: Key.afternoonMinute) as? Int ?? 0
            )
        }
        set {
            UserDefaults.standard.set(newValue.enabled, forKey: Key.afternoonEnabled)
            UserDefaults.standard.set(newValue.hour, forKey: Key.afternoonHour)
            UserDefaults.standard.set(newValue.minute, forKey: Key.afternoonMinute)
        }
    }

    var eveningConfig: DayPartConfig {
        get {
            DayPartConfig(
                enabled: UserDefaults.standard.bool(forKey: Key.eveningEnabled),
                hour: UserDefaults.standard.object(forKey: Key.eveningHour) as? Int ?? 20,
                minute: UserDefaults.standard.object(forKey: Key.eveningMinute) as? Int ?? 0
            )
        }
        set {
            UserDefaults.standard.set(newValue.enabled, forKey: Key.eveningEnabled)
            UserDefaults.standard.set(newValue.hour, forKey: Key.eveningHour)
            UserDefaults.standard.set(newValue.minute, forKey: Key.eveningMinute)
        }
    }

    // MARK: - Permission

    func requestAuthorization() {
        Task {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                print("Notification permission denied: \(error)")
            }
        }
    }

    // MARK: - Delegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Scheduling

    /// Cancel all global reminders and re-schedule enabled ones.
    func rescheduleAll() {
        center.removePendingNotificationRequests(withIdentifiers: [
            ID.morning, ID.afternoon, ID.evening
        ])

        let hasAnyEnabled = morningConfig.enabled || afternoonConfig.enabled || eveningConfig.enabled
        guard hasAnyEnabled else { return }

        // Ensure permission before scheduling
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { self.scheduleEnabled() }
        }
    }

    private func scheduleEnabled() {

        let morning = morningConfig
        if morning.enabled {
            scheduleDaily(
                id: ID.morning,
                title: "Good morning! ☀️",
                body: "Check your activities for today.",
                hour: morning.hour,
                minute: morning.minute
            )
        }

        let afternoon = afternoonConfig
        if afternoon.enabled {
            scheduleDaily(
                id: ID.afternoon,
                title: "Afternoon check-in 📋",
                body: "How's your progress today?",
                hour: afternoon.hour,
                minute: afternoon.minute
            )
        }

        let evening = eveningConfig
        if evening.enabled {
            scheduleDaily(
                id: ID.evening,
                title: "Evening wrap-up 🌙",
                body: "Don't forget to log your remaining activities!",
                hour: evening.hour,
                minute: evening.minute
            )
        }
    }

    // MARK: - Private

    private func scheduleDaily(id: String, title: String, body: String, hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var dc = DateComponents()
        dc.hour = hour
        dc.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        Task { try? await center.add(request) }
    }
}
