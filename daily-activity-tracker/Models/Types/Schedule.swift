import Foundation

enum ScheduleType: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily
    case weekly
    case monthly
    case sticky
    case adhoc

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .sticky: return "Until Done"
        case .adhoc: return "One-time"
        }
    }
}

struct Schedule: Codable, Equatable, Sendable {
    var type: ScheduleType
    var weekdays: [Int]?      // 1=Mon..7=Sun (ISO)
    var monthDays: [Int]?     // 1..31
    var specificDate: Date?   // adhoc only

    static var daily: Schedule { Schedule(type: .daily) }
    static func weekly(_ days: [Int]) -> Schedule { Schedule(type: .weekly, weekdays: days) }
    static func monthly(_ days: [Int]) -> Schedule { Schedule(type: .monthly, monthDays: days) }
    static var sticky: Schedule { Schedule(type: .sticky) }
    static func adhoc(_ date: Date) -> Schedule { Schedule(type: .adhoc, specificDate: date) }

    /// Whether this schedule requires an activity to be shown on the given date.
    /// `.sticky` and `.adhoc` (without match) return false — handled by shouldShow/carry-forward.
    func isScheduled(on date: Date) -> Bool {
        switch type {
        case .daily:
            return true
        case .weekly:
            return (weekdays ?? []).contains(date.weekdayISO)
        case .monthly:
            return (monthDays ?? []).contains(date.dayOfMonth)
        case .sticky, .adhoc:
            return false
        }
    }
}
