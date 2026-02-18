import Foundation
import SwiftData

/// A logged cardio workout session — stores snapshot metadata + HealthKit reference.
@Model
final class CardioSession {
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
    var sessionTypeRaw: String = CardioSessionType.free.rawValue
    var notes: String?

    // HealthKit
    var hkWorkoutID: String?

    // Optional live reference (nullified if plan deleted)
    var planDay: WorkoutPlanDay?

    @Relationship(deleteRule: .cascade, inverse: \CardioSessionLog.session)
    var logs: [CardioSessionLog] = []

    // MARK: - Computed

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .inProgress }
        set { statusRaw = newValue.rawValue }
    }

    var sessionType: CardioSessionType {
        get { CardioSessionType(rawValue: sessionTypeRaw) ?? .free }
        set { sessionTypeRaw = newValue.rawValue }
    }

    var activeDuration: TimeInterval {
        let end = endedAt ?? Date()
        var paused = totalPausedSeconds
        if let pausedAt = pausedAt {
            paused += end.timeIntervalSince(pausedAt)
        }
        return end.timeIntervalSince(startedAt) - paused
    }

    var durationFormatted: String {
        let total = Int(activeDuration)
        let min = total / 60
        let sec = total % 60
        return String(format: "%d:%02d", min, sec)
    }

    // MARK: - Init

    init(planName: String, dayLabel: String, weekday: Int, sessionType: CardioSessionType, planDay: WorkoutPlanDay? = nil) {
        self.id = UUID()
        self.planName = planName
        self.dayLabel = dayLabel
        self.weekday = weekday
        self.date = Date()
        self.startedAt = Date()
        self.sessionTypeRaw = sessionType.rawValue
        self.planDay = planDay
    }
}

// MARK: - Cardio Session Log (per-exercise metrics from a session)

@Model
final class CardioSessionLog {
    var id: UUID = UUID()

    // Core metrics
    var distance: Double?
    var durationSeconds: Int = 0
    var avgPace: Double?      // seconds per unit (e.g. sec/km)
    var avgSpeed: Double?     // km/h
    var calories: Double?
    var elevationGain: Double?

    // Heart rate
    var avgHeartRate: Int?
    var maxHeartRate: Int?
    var heartRateZonesData: Data?  // JSON: [Int] — seconds in each zone (Z1–Z5)

    // Swim / Row specific
    var avgCadence: Int?
    var strokeCount: Int?
    var strokeType: String?
    var swolf: Int?
    var laps: Int?

    // References
    var exerciseID: UUID?
    var session: CardioSession?

    // MARK: - Computed

    var heartRateZones: [Int] {
        get {
            guard let data = heartRateZonesData,
                  let arr = try? JSONDecoder().decode([Int].self, from: data) else { return [] }
            return arr
        }
        set {
            heartRateZonesData = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue))
        }
    }

    /// Formatted pace (e.g. "7:25 /km")
    func formattedPace(unit: String = "/km") -> String? {
        guard let pace = avgPace, pace > 0 else { return nil }
        let min = Int(pace) / 60
        let sec = Int(pace) % 60
        return "\(min):\(String(format: "%02d", sec)) \(unit)"
    }

    // MARK: - Init

    init(exerciseID: UUID? = nil) {
        self.id = UUID()
        self.exerciseID = exerciseID
    }
}
