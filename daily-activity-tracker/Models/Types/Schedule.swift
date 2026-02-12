import Foundation

enum ScheduleType: String, Codable, CaseIterable, Identifiable {
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

struct Schedule: Codable, Equatable {
    var type: ScheduleType
    var weekdays: [Int]?      // 1=Mon..7=Sun (ISO)
    var monthDays: [Int]?     // 1..31
    var specificDate: Date?   // adhoc only

    static var daily: Schedule { Schedule(type: .daily) }
    static func weekly(_ days: [Int]) -> Schedule { Schedule(type: .weekly, weekdays: days) }
    static func monthly(_ days: [Int]) -> Schedule { Schedule(type: .monthly, monthDays: days) }
    static var sticky: Schedule { Schedule(type: .sticky) }
    static func adhoc(_ date: Date) -> Schedule { Schedule(type: .adhoc, specificDate: date) }
}
