import Foundation
import SwiftData

/// Pre-seeds the exercise library with common strength and cardio exercises.
/// Called once on first launch when the exercise table is empty.
struct ExerciseSeeder {

    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.isPreSeeded == true })
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        let muscles = seedMusclesIfNeeded(context: context)
        seedStrengthExercises(context: context, muscles: muscles)
        seedCardioExercises(context: context)

        try? context.save()
    }

    // MARK: - Muscle Glossary

    static func seedMusclesIfNeeded(context: ModelContext) -> [String: UUID] {
        let descriptor = FetchDescriptor<MuscleGroup>(predicate: #Predicate { $0.isPreSeeded == true })
        let existing = (try? context.fetch(descriptor)) ?? []
        if !existing.isEmpty {
            return Dictionary(uniqueKeysWithValues: existing.map { ($0.name, $0.id) })
        }

        let all = MuscleGroup.buildGlossary()
        for m in all { context.insert(m) }
        return Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0.id) })
    }

    // MARK: - Strength Exercises

    private static func seedStrengthExercises(context: ModelContext, muscles: [String: UUID]) {

        // Helper: create exercise + attach muscle involvements
        func str(_ name: String, _ equipment: String, _ involvements: [(String, Double)], aliases: [String] = []) {
            let ex = Exercise(name: name, equipment: equipment, type: .strength, isPreSeeded: true)
            ex.aliases = aliases
            context.insert(ex)
            for (muscleName, score) in involvements {
                if let muscleID = muscles[muscleName] {
                    let em = ExerciseMuscle(muscleGroupID: muscleID, score: score)
                    em.exercise = ex
                    context.insert(em)
                }
            }
        }

        // Chest
        str("Bench Press", "Barbell", [
            ("Upper Chest", 0.4), ("Lower Chest", 0.8), ("Front Delts", 0.5), ("Triceps", 0.5)
        ], aliases: ["Flat Bench", "BB Bench"])

        str("Incline Bench Press", "Dumbbell", [
            ("Upper Chest", 0.9), ("Lower Chest", 0.3), ("Front Delts", 0.6), ("Triceps", 0.4)
        ], aliases: ["Incline DB Press"])

        str("Cable Fly", "Cable", [
            ("Upper Chest", 0.5), ("Lower Chest", 0.7), ("Front Delts", 0.2)
        ])

        // Back
        str("Barbell Row", "Barbell", [
            ("Lats", 0.7), ("Upper Back / Traps", 0.6), ("Rhomboids", 0.5), ("Biceps", 0.4)
        ], aliases: ["Bent Over Row", "BB Row"])

        str("Pull Up", "Bodyweight", [
            ("Lats", 0.9), ("Biceps", 0.5), ("Rhomboids", 0.3), ("Lower Back / Erectors", 0.2)
        ], aliases: ["Pullup", "Chin Up"])

        str("Lat Pulldown", "Cable", [
            ("Lats", 0.8), ("Biceps", 0.4), ("Upper Back / Traps", 0.3)
        ])

        // Shoulders
        str("Overhead Press", "Barbell", [
            ("Front Delts", 0.9), ("Side Delts", 0.4), ("Triceps", 0.5)
        ], aliases: ["OHP", "Military Press"])

        str("Lateral Raise", "Dumbbell", [
            ("Side Delts", 0.9), ("Front Delts", 0.2)
        ], aliases: ["Side Raise"])

        str("Face Pull", "Cable", [
            ("Rear Delts", 0.8), ("Upper Back / Traps", 0.4), ("Rhomboids", 0.3)
        ])

        // Arms
        str("Barbell Curl", "Barbell", [
            ("Biceps", 0.9), ("Forearms", 0.3)
        ], aliases: ["BB Curl"])

        str("Tricep Pushdown", "Cable", [
            ("Lateral Head", 0.8), ("Medial Head", 0.5), ("Long Head", 0.3)
        ], aliases: ["Rope Pushdown"])

        // Legs
        str("Squat", "Barbell", [
            ("Vastus Lateralis", 0.8), ("Vastus Medialis", 0.7), ("Rectus Femoris", 0.6),
            ("Glute Max", 0.7), ("Lower Back / Erectors", 0.4), ("Core", 0.3)
        ], aliases: ["Back Squat", "BB Squat"])

        str("Romanian Deadlift", "Barbell", [
            ("Hamstrings", 0.9), ("Glute Max", 0.7), ("Lower Back / Erectors", 0.6)
        ], aliases: ["RDL"])

        str("Leg Press", "Machine", [
            ("Vastus Lateralis", 0.8), ("Vastus Medialis", 0.7), ("Glute Max", 0.5)
        ])

        str("Calf Raise", "Machine", [
            ("Gastrocnemius", 0.8), ("Soleus", 0.6)
        ], aliases: ["Standing Calf Raise"])
    }

    // MARK: - Cardio Exercises

    private static func seedCardioExercises(context: ModelContext) {

        func cardio(_ name: String, _ equipment: String, distUnit: String, paceUnit: String, metrics: [CardioMetric]) {
            let ex = Exercise(name: name, equipment: equipment, type: .cardio, isPreSeeded: true)
            ex.distanceUnit = distUnit
            ex.paceUnit = paceUnit
            ex.availableMetrics = metrics
            context.insert(ex)
        }

        cardio("Running", "Outdoors", distUnit: "km", paceUnit: "min/km", metrics: CardioMetric.runningMetrics)
        cardio("Treadmill Run", "Treadmill", distUnit: "km", paceUnit: "min/km", metrics: CardioMetric.runningMetrics)
        cardio("Swimming", "Pool", distUnit: "m", paceUnit: "/100m", metrics: CardioMetric.swimmingMetrics)
        cardio("Cycling", "Outdoor Bike", distUnit: "km", paceUnit: "km/h", metrics: CardioMetric.cyclingMetrics)
        cardio("Rowing", "Rowing Machine", distUnit: "m", paceUnit: "/500m", metrics: CardioMetric.rowingMetrics)
    }
}
