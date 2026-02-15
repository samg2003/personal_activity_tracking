import Foundation

/// Defines how often a photo should be captured for an activity
enum PhotoCadence: String, Codable, CaseIterable, Identifiable, Sendable {
    case everyTime = "every_time"
    case weekly    = "weekly"
    case monthly   = "monthly"
    case never     = "never"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .everyTime: return "Every Time"
        case .weekly:    return "Weekly"
        case .monthly:   return "Monthly"
        case .never:     return "Never"
        }
    }

    var description: String {
        switch self {
        case .everyTime: return "Prompt for a photo each completion"
        case .weekly:    return "Prompt once per week"
        case .monthly:   return "Prompt once per month"
        case .never:     return "No photo prompts"
        }
    }
}
