import Foundation
import SwiftData

/// A cardio exercise entry within a plan day — defines session type + target.
@Model
final class CardioPlanExercise {
    var id: UUID = UUID()
    var sessionTypeRaw: String = CardioSessionType.free.rawValue
    var targetDistance: Double?    // In exercise's distance unit
    var targetDurationMin: Int?   // Minutes
    var sessionParamsData: Data?  // JSON: type-specific params
    var sortOrder: Int = 0

    var exercise: Exercise?
    var planDay: WorkoutPlanDay?

    // MARK: - Computed

    var sessionType: CardioSessionType {
        get { CardioSessionType(rawValue: sessionTypeRaw) ?? .free }
        set { sessionTypeRaw = newValue.rawValue }
    }

    /// Target description (e.g. "5 km" or "30 min")
    var targetLabel: String {
        if let dist = targetDistance, let ex = exercise {
            return "\(formatDistance(dist)) \(ex.distanceUnit ?? "km")"
        } else if let dur = targetDurationMin {
            return "\(dur) min"
        }
        return "No target"
    }

    // MARK: - Session Params

    var steadyStateParams: SteadyStateParams? {
        get { decodeParams() }
        set { encodeParams(newValue) }
    }

    var tempoParams: TempoParams? {
        get { decodeParams() }
        set { encodeParams(newValue) }
    }

    var hiitParams: HIITParams? {
        get { decodeParams() }
        set { encodeParams(newValue) }
    }

    var intervalParams: IntervalParams? {
        get { decodeParams() }
        set { encodeParams(newValue) }
    }

    // MARK: - Init

    init(
        exercise: Exercise,
        sessionType: CardioSessionType = .free,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.exercise = exercise
        self.sessionTypeRaw = sessionType.rawValue
        self.sortOrder = sortOrder
    }

    // MARK: - Helpers

    private func decodeParams<T: Decodable>() -> T? {
        guard let data = sessionParamsData else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encodeParams<T: Encodable>(_ params: T?) {
        sessionParamsData = params.flatMap { try? JSONEncoder().encode($0) }
    }

    private func formatDistance(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
