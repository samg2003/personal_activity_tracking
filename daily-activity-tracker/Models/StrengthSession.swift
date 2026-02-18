import Foundation
import SwiftData

/// A logged strength workout session — stores snapshot metadata for history preservation.
@Model
final class StrengthSession {
    var id: UUID = UUID()

    // Snapshot (survives plan deletion)
    var planName: String = ""
    var dayLabel: String = ""
    var weekday: Int = 1

    // Timing
    var date: Date = Date()
    var startedAt: Date = Date()
    var pausedAt: Date?
    var endedAt: Date?
    var totalPausedSeconds: Double = 0
    var statusRaw: String = SessionStatus.inProgress.rawValue
    var notes: String?

    /// When a completed session is resumed, stores the set count at resume time.
    /// On abandon, sets added after this index are removed and the session reverts to completed.
    /// -1 means session was started fresh (not resumed).
    var resumedAtSetCount: Int = -1
    /// Timing snapshot at resume — restored on abandon so duration stays accurate.
    var resumedAtEndedAt: Date?
    var resumedAtPausedSeconds: Double = -1

    // Optional live reference (nullified if plan deleted)
    var planDay: WorkoutPlanDay?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSetLog.session)
    var setLogs: [WorkoutSetLog] = []

    // MARK: - Computed

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .inProgress }
        set { statusRaw = newValue.rawValue }
    }

    /// Active duration excluding pauses
    var activeDuration: TimeInterval {
        let end = endedAt ?? Date()
        var paused = totalPausedSeconds
        // Subtract ongoing pause interval if currently paused
        if let pausedAt = pausedAt {
            paused += end.timeIntervalSince(pausedAt)
        }
        return end.timeIntervalSince(startedAt) - paused
    }

    /// Formatted duration (e.g. "45:23")
    var durationFormatted: String {
        let total = Int(activeDuration)
        let min = total / 60
        let sec = total % 60
        return String(format: "%d:%02d", min, sec)
    }

    /// Completed (non-warmup) sets
    var completedSets: [WorkoutSetLog] {
        setLogs.filter { !$0.isWarmup }
    }

    // MARK: - Init

    init(planName: String, dayLabel: String, weekday: Int, planDay: WorkoutPlanDay? = nil) {
        self.id = UUID()
        self.planName = planName
        self.dayLabel = dayLabel
        self.weekday = weekday
        self.date = Date()
        self.startedAt = Date()
        self.planDay = planDay
    }
}

// MARK: - Set Log

@Model
final class WorkoutSetLog {
    var id: UUID = UUID()
    var setNumber: Int = 1
    var reps: Int = 0
    var weight: Double = 0
    var durationSeconds: Int?  // Timed exercises (deadhang, plank)
    var isWarmup: Bool = false
    var completedAt: Date = Date()

    var exercise: Exercise?
    var session: StrengthSession?

    // MARK: - Computed

    /// Estimated 1RM via Brzycki: weight × 36 / (37 - reps)
    var estimated1RM: Double? {
        guard reps > 0 && reps < 37 && weight > 0 else { return nil }
        return weight * 36.0 / (37.0 - Double(reps))
    }

    // MARK: - Init

    init(exercise: Exercise, setNumber: Int, reps: Int, weight: Double, isWarmup: Bool = false) {
        self.id = UUID()
        self.exercise = exercise
        self.setNumber = setNumber
        self.reps = reps
        self.weight = weight
        self.isWarmup = isWarmup
        self.completedAt = Date()
    }
}

// MARK: - Session Status (shared by strength + cardio)

enum SessionStatus: String, Codable, CaseIterable {
    case inProgress
    case paused
    case completed
    case abandoned
}
