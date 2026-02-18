import Foundation

enum WorkoutPlanStatus: String, Codable, CaseIterable, Identifiable {
    case draft
    case active
    case inactive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .active: return "Active"
        case .inactive: return "Inactive"
        }
    }

    var icon: String {
        switch self {
        case .draft: return "pencil.circle"
        case .active: return "checkmark.circle.fill"
        case .inactive: return "pause.circle"
        }
    }
}
