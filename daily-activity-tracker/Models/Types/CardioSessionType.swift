import Foundation

enum CardioSessionType: String, Codable, CaseIterable, Identifiable {
    case steadyState
    case hiit
    case tempo
    case intervals
    case free

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .steadyState: return "Steady State (Zone 2)"
        case .hiit: return "HIIT"
        case .tempo: return "Tempo"
        case .intervals: return "Intervals"
        case .free: return "Free"
        }
    }

    var icon: String {
        switch self {
        case .steadyState: return "heart.circle"
        case .hiit: return "bolt.circle"
        case .tempo: return "gauge.with.dots.needle.33percent"
        case .intervals: return "repeat.circle"
        case .free: return "figure.run.circle"
        }
    }

    var description: String {
        switch self {
        case .steadyState: return "Stay in a target HR zone for the duration"
        case .hiit: return "Alternating high-intensity and recovery rounds"
        case .tempo: return "Warmup → sustained effort → cooldown"
        case .intervals: return "Repeated distance efforts with rest between"
        case .free: return "Track metrics without structured guidance"
        }
    }
}

// MARK: - Session Parameter Structs

struct SteadyStateParams: Codable, Equatable {
    var targetHRZone: Int // 1–5
}

struct TempoParams: Codable, Equatable {
    var warmupMin: Int
    var tempoMin: Int
    var cooldownMin: Int
    var targetHRZone: Int // 1–5

    var totalMinutes: Int { warmupMin + tempoMin + cooldownMin }
}

struct HIITParams: Codable, Equatable {
    var rounds: Int
    var workSeconds: Int
    var restSeconds: Int

    var totalSeconds: Int { rounds * (workSeconds + restSeconds) }
}

struct IntervalParams: Codable, Equatable {
    var reps: Int
    var distancePerRep: Double
    var restSeconds: Int
}
