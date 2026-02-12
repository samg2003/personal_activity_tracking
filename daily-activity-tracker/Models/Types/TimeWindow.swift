import Foundation

enum TimeSlot: String, Codable, CaseIterable, Identifiable, Comparable {
    case allDay
    case morning
    case afternoon
    case evening

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allDay: return "All Day"
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        }
    }

    var icon: String {
        switch self {
        case .allDay: return "arrow.2.circlepath"
        case .morning: return "sunrise"
        case .afternoon: return "sun.max"
        case .evening: return "moon"
        }
    }

    /// Rough hour boundary for auto-collapse logic
    var startHour: Int {
        switch self {
        case .allDay: return 0
        case .morning: return 5
        case .afternoon: return 12
        case .evening: return 17
        }
    }

    private var sortIndex: Int {
        switch self {
        case .allDay: return 0
        case .morning: return 1
        case .afternoon: return 2
        case .evening: return 3
        }
    }

    static func < (lhs: TimeSlot, rhs: TimeSlot) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }
}

struct TimeWindow: Codable, Equatable {
    var slot: TimeSlot
    var customStartHour: Int?
    var customEndHour: Int?

    static var allDay: TimeWindow { TimeWindow(slot: .allDay) }
    static var morning: TimeWindow { TimeWindow(slot: .morning) }
    static var afternoon: TimeWindow { TimeWindow(slot: .afternoon) }
    static var evening: TimeWindow { TimeWindow(slot: .evening) }
}
