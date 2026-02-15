import Foundation

/// The kind of measurement a metric activity tracks. Exactly one per metric.
enum MetricKind: String, Codable, CaseIterable, Identifiable {
    case photo     // Progress photos
    case value     // Numeric (body fat %, weight, deadhang time)
    case checkbox  // Boolean milestone (achieved / not yet)
    case notes     // Qualitative text

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .photo: return "Photo"
        case .value: return "Value"
        case .checkbox: return "Checkbox"
        case .notes: return "Notes"
        }
    }

    var systemImage: String {
        switch self {
        case .photo: return "camera.fill"
        case .value: return "number"
        case .checkbox: return "checkmark.circle"
        case .notes: return "text.alignleft"
        }
    }
}
