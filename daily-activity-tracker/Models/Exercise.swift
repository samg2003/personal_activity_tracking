import Foundation
import SwiftData

/// An exercise in the workout domain — not an Activity. Shared by both strength and cardio plans.
@Model
final class Exercise {
    var id: UUID = UUID()
    var name: String = ""
    var equipment: String = ""
    var exerciseTypeRaw: String = "strength"
    var aliasesData: Data?
    var isPreSeeded: Bool = false
    var createdAt: Date = Date()
    var notes: String?
    var videoURLsData: Data?

    /// Multiple video URLs (YouTube, etc.) for exercise demos.
    var videoURLs: [String] {
        get {
            guard let data = videoURLsData,
                  let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return arr
        }
        set {
            videoURLsData = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue))
        }
    }

    /// Convenience: first video URL (backward compat).
    var videoURL: String? {
        get { videoURLs.first }
        set {
            if let url = newValue {
                if videoURLs.isEmpty { videoURLs = [url] }
                else { videoURLs[0] = url }
            } else {
                if !videoURLs.isEmpty { videoURLs.removeFirst() }
            }
        }
    }

    // Cardio-specific (nil for strength)
    var distanceUnit: String?
    var paceUnit: String?
    var availableMetricsData: Data?

    // MARK: - Relationships

    @Relationship(deleteRule: .cascade, inverse: \ExerciseMuscle.exercise)
    var muscleInvolvements: [ExerciseMuscle] = []

    // MARK: - Computed

    var displayName: String { "\(name) – \(equipment)" }

    var exerciseType: ExerciseType {
        get { ExerciseType(rawValue: exerciseTypeRaw) ?? .strength }
        set { exerciseTypeRaw = newValue.rawValue }
    }

    var aliases: [String] {
        get {
            guard let data = aliasesData,
                  let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return arr
        }
        set {
            aliasesData = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue))
        }
    }

    var availableMetrics: [CardioMetric] {
        get {
            guard let data = availableMetricsData,
                  let arr = try? JSONDecoder().decode([CardioMetric].self, from: data) else { return [] }
            return arr
        }
        set {
            availableMetricsData = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue))
        }
    }

    /// All searchable names: canonical display name + aliases
    var searchableNames: [String] {
        [displayName] + aliases
    }

    // MARK: - Init

    init(
        name: String,
        equipment: String,
        type: ExerciseType = .strength,
        isPreSeeded: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.equipment = equipment
        self.exerciseTypeRaw = type.rawValue
        self.isPreSeeded = isPreSeeded
        self.createdAt = Date()
    }
}

// MARK: - Exercise Type

enum ExerciseType: String, Codable, CaseIterable, Identifiable {
    case strength
    case cardio
    case timed   // deadhang, plank — logs duration instead of reps

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strength: return "Strength"
        case .cardio: return "Cardio"
        case .timed: return "Timed"
        }
    }
}

// MARK: - Exercise ↔ Muscle junction

@Model
final class ExerciseMuscle {
    var id: UUID = UUID()
    var involvementScore: Double = 0.5 // 0.0–1.0
    var exercise: Exercise?
    var muscleGroupID: UUID?

    init(muscleGroupID: UUID, score: Double) {
        self.id = UUID()
        self.muscleGroupID = muscleGroupID
        self.involvementScore = score
    }
}
