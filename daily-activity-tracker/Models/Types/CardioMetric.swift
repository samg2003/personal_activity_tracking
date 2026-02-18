import Foundation

/// Defines which HealthKit metrics are available for a given cardio exercise type.
enum CardioMetric: String, Codable, CaseIterable, Identifiable {
    case duration
    case distance
    case pace
    case speed
    case heartRate
    case heartRateZones
    case calories
    case cadence
    case strokeCount
    case strokeType
    case swolf
    case laps
    case elevation

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .duration: return "Duration"
        case .distance: return "Distance"
        case .pace: return "Pace"
        case .speed: return "Speed"
        case .heartRate: return "Heart Rate"
        case .heartRateZones: return "HR Zones"
        case .calories: return "Calories"
        case .cadence: return "Cadence"
        case .strokeCount: return "Strokes"
        case .strokeType: return "Stroke Type"
        case .swolf: return "SWOLF"
        case .laps: return "Laps"
        case .elevation: return "Elevation"
        }
    }

    var unit: String {
        switch self {
        case .duration: return "min"
        case .distance: return "" // exercise-specific
        case .pace: return "" // exercise-specific
        case .speed: return "km/h"
        case .heartRate: return "bpm"
        case .heartRateZones: return ""
        case .calories: return "kcal"
        case .cadence: return "spm"
        case .strokeCount: return ""
        case .strokeType: return ""
        case .swolf: return ""
        case .laps: return ""
        case .elevation: return "m"
        }
    }

    var icon: String {
        switch self {
        case .duration: return "clock"
        case .distance: return "ruler"
        case .pace: return "speedometer"
        case .speed: return "gauge.with.dots.needle.67percent"
        case .heartRate: return "heart.fill"
        case .heartRateZones: return "chart.bar.fill"
        case .calories: return "flame.fill"
        case .cadence: return "metronome"
        case .strokeCount: return "drop.fill"
        case .strokeType: return "figure.pool.swim"
        case .swolf: return "number"
        case .laps: return "arrow.counterclockwise"
        case .elevation: return "mountain.2"
        }
    }

    /// Default metrics available per exercise category
    static var runningMetrics: [CardioMetric] {
        [.duration, .distance, .pace, .heartRate, .heartRateZones, .calories, .cadence, .elevation]
    }

    static var swimmingMetrics: [CardioMetric] {
        [.duration, .distance, .pace, .heartRate, .heartRateZones, .calories, .strokeCount, .strokeType, .swolf, .laps]
    }

    static var cyclingMetrics: [CardioMetric] {
        [.duration, .distance, .speed, .heartRate, .heartRateZones, .calories, .cadence, .elevation]
    }

    static var rowingMetrics: [CardioMetric] {
        [.duration, .distance, .heartRate, .heartRateZones, .calories, .cadence, .strokeCount]
    }
}
