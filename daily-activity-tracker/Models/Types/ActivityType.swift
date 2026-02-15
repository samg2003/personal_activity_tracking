import Foundation

enum ActivityType: String, Codable, CaseIterable, Identifiable {
    case checkbox
    case value
    case cumulative
    case container
    case metric

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .checkbox: return "Checkbox"
        case .value: return "Value"
        case .cumulative: return "Cumulative"
        case .container: return "Container"
        case .metric: return "Metric"
        }
    }

    var systemImage: String {
        switch self {
        case .checkbox: return "checkmark.circle"
        case .value: return "number"
        case .cumulative: return "chart.bar.fill"
        case .container: return "folder"
        case .metric: return "chart.line.uptrend.xyaxis"
        }
    }
}
