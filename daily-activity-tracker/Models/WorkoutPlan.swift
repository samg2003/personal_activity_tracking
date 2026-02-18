import Foundation
import SwiftData

@Model
final class WorkoutPlan {
    var id: UUID = UUID()
    var name: String = ""
    var planTypeRaw: String = "strength"
    var statusRaw: String = WorkoutPlanStatus.draft.rawValue
    var containerActivityID: UUID?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \WorkoutPlanDay.plan)
    var days: [WorkoutPlanDay] = []

    // MARK: - Computed

    var planType: ExerciseType {
        get { ExerciseType(rawValue: planTypeRaw) ?? .strength }
        set { planTypeRaw = newValue.rawValue }
    }

    var status: WorkoutPlanStatus {
        get { WorkoutPlanStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var isActive: Bool { status == .active }
    var isDraft: Bool { status == .draft }

    /// Sorted days Mon(1) → Sun(7)
    var sortedDays: [WorkoutPlanDay] {
        days.sorted { $0.weekday < $1.weekday }
    }

    /// Non-rest days with exercises
    var trainingDays: [WorkoutPlanDay] {
        sortedDays.filter { !$0.isRest }
    }

    // MARK: - Init

    init(name: String, planType: ExerciseType) {
        self.id = UUID()
        self.name = name
        self.planTypeRaw = planType.rawValue
        self.statusRaw = WorkoutPlanStatus.draft.rawValue
        self.createdAt = Date()
    }
}

// MARK: - Plan Day

@Model
final class WorkoutPlanDay: Identifiable {
    var id: UUID = UUID()
    var weekday: Int = 1       // 1=Mon..7=Sun (ISO)
    var dayLabel: String = ""  // "Push", "Pull", "Legs", or user override
    var isLabelOverridden: Bool = false
    var isRest: Bool = false
    var colorGroup: Int = -1   // -1=unlinked, 0–6=rainbow link group

    var plan: WorkoutPlan?

    @Relationship(deleteRule: .cascade, inverse: \StrengthPlanExercise.planDay)
    var strengthExercises: [StrengthPlanExercise] = []

    @Relationship(deleteRule: .cascade, inverse: \CardioPlanExercise.planDay)
    var cardioExercises: [CardioPlanExercise] = []

    // MARK: - Computed

    var weekdayName: String {
        let names = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        guard weekday >= 1 && weekday <= 7 else { return "" }
        return names[weekday]
    }

    var weekdayFullName: String {
        let names = ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        guard weekday >= 1 && weekday <= 7 else { return "" }
        return names[weekday]
    }

    var isLinked: Bool { colorGroup >= 0 }

    /// Total planned sets for strength days
    var totalSets: Int {
        strengthExercises.reduce(0) { $0 + $1.targetSets }
    }

    /// Whether this day has any exercises (strength or cardio)
    var hasExercises: Bool {
        !strengthExercises.isEmpty || !cardioExercises.isEmpty
    }

    /// Sorted strength exercises by sort order
    var sortedStrengthExercises: [StrengthPlanExercise] {
        strengthExercises.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Sorted cardio exercises by sort order
    var sortedCardioExercises: [CardioPlanExercise] {
        cardioExercises.sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Color Linking

    /// Rainbow colors for day linking
    static let linkColors: [(name: String, emoji: String)] = [
        ("Red", "🔴"), ("Orange", "🟠"), ("Yellow", "🟡"),
        ("Green", "🟢"), ("Blue", "🔵"), ("Purple", "🟣"), ("White", "⚪")
    ]

    var colorEmoji: String {
        guard isLinked, colorGroup >= 0, colorGroup < Self.linkColors.count else { return "⚫" }
        return Self.linkColors[colorGroup].emoji
    }

    // MARK: - Init

    init(weekday: Int, plan: WorkoutPlan? = nil) {
        self.id = UUID()
        self.weekday = weekday
        self.plan = plan
    }
}
