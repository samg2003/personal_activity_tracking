import Foundation
import SwiftData

/// A strength exercise entry within a plan day — defines target sets/RIR.
@Model
final class StrengthPlanExercise {
    var id: UUID = UUID()
    var targetSets: Int = 3
    var rir: Int = 2             // Reps In Reserve, default 2
    var sortOrder: Int = 0
    var supersetGroup: String?   // e.g. "A", "B" — same group = superset

    var exercise: Exercise?
    var planDay: WorkoutPlanDay?

    // MARK: - Computed

    /// Compact display: "(4) Bench – BB"
    var compactLabel: String {
        guard let ex = exercise else { return "(\(targetSets)) Unknown" }
        let shortName = ex.name.prefix(8)
        let shortEquip = String(ex.equipment.prefix(2))
        return "(\(targetSets)) \(shortName) – \(shortEquip)"
    }

    // MARK: - Init

    init(exercise: Exercise, targetSets: Int = 3, rir: Int = 2, sortOrder: Int = 0) {
        self.id = UUID()
        self.exercise = exercise
        self.targetSets = targetSets
        self.rir = rir
        self.sortOrder = sortOrder
    }
}
