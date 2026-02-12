import Foundation

/// Notification presets — smart defaults so users don't build raw conditions.
enum ReminderPreset: Codable, Equatable {
    case remindAt(hour: Int, minute: Int)
    case morningNudge        // 8 AM if not started
    case eveningCheckIn      // 8 PM if < 50%
    case periodic(hours: Int) // every N hrs if behind
    case none
}
