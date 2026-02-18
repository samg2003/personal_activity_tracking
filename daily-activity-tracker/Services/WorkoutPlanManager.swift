import Foundation
import SwiftData

/// Manages workout plan lifecycle: CRUD, shell activity synchronization,
/// volume analysis, and day-type auto-detection.
@Observable
final class WorkoutPlanManager {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Plan CRUD

    /// Creates a new plan with 7 days (Mon–Sun), all initially set as rest.
    func createPlan(name: String, planType: ExerciseType) -> WorkoutPlan {
        let plan = WorkoutPlan(name: name, planType: planType)
        modelContext.insert(plan)

        for weekday in 1...7 {
            let day = WorkoutPlanDay(weekday: weekday, plan: plan)
            day.isRest = true
            modelContext.insert(day)
        }

        try? modelContext.save()
        return plan
    }

    /// Activates a plan — auto-deactivates any other active plan of same type.
    func activatePlan(_ plan: WorkoutPlan) {
        // Deactivate current active plan of same type
        if let current = fetchActivePlan(type: plan.planType) {
            deactivatePlan(current)
        }

        plan.status = .active
        syncShellActivities(for: plan)
        try? modelContext.save()
    }

    /// Deactivates a plan — shells get stoppedAt, disappear from dashboard.
    func deactivatePlan(_ plan: WorkoutPlan) {
        plan.status = .inactive
        let shells = fetchShells(for: plan)
        for shell in shells {
            shell.stoppedAt = Date()
        }
        try? modelContext.save()
    }

    /// Deletes a plan (marks inactive, stops shells). Data preserved for history.
    func deletePlan(_ plan: WorkoutPlan) {
        deactivatePlan(plan)
    }

    // MARK: - Plan Queries

    func fetchActivePlan(type: ExerciseType) -> WorkoutPlan? {
        let typeRaw = type.rawValue
        let activeRaw = WorkoutPlanStatus.active.rawValue
        let descriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate { $0.planTypeRaw == typeRaw && $0.statusRaw == activeRaw }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func fetchAllPlans() -> [WorkoutPlan] {
        let inactiveRaw = WorkoutPlanStatus.inactive.rawValue
        let descriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate { $0.statusRaw != inactiveRaw },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Shell Activity Synchronization

    /// Syncs shell activities for a plan: creates/updates shells with correct schedules.
    /// Non-linked days with the same label get numbered ("Push 1", "Push 2").
    func syncShellActivities(for plan: WorkoutPlan) {
        guard plan.isActive else { return }

        let container = findOrCreateContainer(for: plan)
        let trainingDays = plan.days.filter { !$0.isRest }

        // Build shell labels: linked days share one shell, non-linked get disambiguated
        var shellSpecs: [(label: String, weekdays: [Int])] = []
        var handledIDs = Set<UUID>()

        for day in trainingDays {
            guard !handledIDs.contains(day.id) else { continue }

            if day.isLinked, let plan = day.plan {
                // Linked days: merge all days with same colorGroup into one shell
                let linked = plan.days.filter { $0.colorGroup == day.colorGroup && !$0.isRest }
                let weekdays = linked.map(\.weekday)
                linked.forEach { handledIDs.insert($0.id) }
                shellSpecs.append((label: day.dayLabel, weekdays: weekdays))
            } else {
                handledIDs.insert(day.id)
                shellSpecs.append((label: day.dayLabel, weekdays: [day.weekday]))
            }
        }

        // Disambiguate duplicate labels with numbering
        let labelCounts = Dictionary(grouping: shellSpecs, by: { $0.label })
        var labelCounters: [String: Int] = [:]
        shellSpecs = shellSpecs.map { spec in
            if (labelCounts[spec.label]?.count ?? 0) > 1 {
                let n = (labelCounters[spec.label] ?? 0) + 1
                labelCounters[spec.label] = n
                return (label: "\(spec.label) \(n)", weekdays: spec.weekdays)
            }
            return spec
        }

        var activeShellIDs = Set<UUID>()

        for spec in shellSpecs {
            let shell = findOrCreateShell(plan: plan, label: spec.label, container: container)
            updateShellSchedule(shell, weekdays: spec.weekdays)
            activeShellIDs.insert(shell.id)
        }

        // Stop shells for labels no longer in the plan
        let allShells = fetchShells(for: plan)
        for shell in allShells where !activeShellIDs.contains(shell.id) {
            shell.stoppedAt = Date()
        }

        try? modelContext.save()
    }

    // MARK: - Day-Type Auto-Detection

    /// Auto-detects day label based on dominant muscle coverage.
    func autoDetectDayLabel(for day: WorkoutPlanDay) -> String {
        guard !day.strengthExercises.isEmpty else { return "Rest" }

        let muscleVolumes = effectiveSetsPerMuscle(for: day)
        guard !muscleVolumes.isEmpty else { return "Full Body" }

        let totalSets = muscleVolumes.values.reduce(0, +)
        guard totalSets > 0 else { return "Full Body" }

        // Find dominant muscle groups (>60% of volume)
        let pushMuscles: Set<String> = ["Chest", "Shoulders", "Triceps"]
        let pullMuscles: Set<String> = ["Back", "Biceps", "Forearms"]
        let legMuscles: Set<String> = ["Quads", "Hamstrings", "Glutes", "Calves"]
        let upperMuscles = pushMuscles.union(pullMuscles)

        var pushVol = 0.0, pullVol = 0.0, legVol = 0.0

        for (muscle, vol) in muscleVolumes {
            if pushMuscles.contains(muscle) { pushVol += vol }
            if pullMuscles.contains(muscle) { pullVol += vol }
            if legMuscles.contains(muscle) { legVol += vol }
        }

        let pushRatio = pushVol / totalSets
        let pullRatio = pullVol / totalSets
        let legRatio = legVol / totalSets
        let upperRatio = (pushVol + pullVol) / totalSets

        // Classification thresholds
        if pushRatio > 0.6 { return "Push" }
        if pullRatio > 0.6 { return "Pull" }
        if legRatio > 0.6 { return "Legs" }
        if upperRatio > 0.8 { return "Upper" }
        if legRatio > 0.8 { return "Lower" }
        return "Full Body"
    }

    // MARK: - Volume Analysis

    /// Computes effective sets per parent muscle group for a single day.
    func effectiveSetsPerMuscle(for day: WorkoutPlanDay) -> [String: Double] {
        var result: [String: Double] = [:]

        for planEx in day.strengthExercises {
            guard let exercise = planEx.exercise else { continue }
            for involvement in exercise.muscleInvolvements {
                guard let muscleID = involvement.muscleGroupID else { continue }
                let muscleName = resolveMuscleParentName(muscleID)
                let effective = Double(planEx.targetSets) * involvement.involvementScore
                result[muscleName, default: 0] += effective
            }
        }

        return result
    }

    /// Weekly volume per muscle across all days in the plan.
    func weeklyVolumePerMuscle(for plan: WorkoutPlan) -> [String: Double] {
        var result: [String: Double] = [:]
        for day in plan.days where !day.isRest {
            let dayVolume = effectiveSetsPerMuscle(for: day)
            for (muscle, vol) in dayVolume {
                result[muscle, default: 0] += vol
            }
        }
        return result
    }

    /// Weekly volume broken down by sub-muscle, grouped under parent.
    /// Returns [parentName: [(childName, effectiveSets)]] — children sorted by volume desc.
    func weeklyVolumePerSubMuscle(for plan: WorkoutPlan) -> [(parent: String, children: [(name: String, sets: Double)])] {
        var childVolumes: [UUID: Double] = [:]  // muscleGroupID → effective sets

        for day in plan.days where !day.isRest {
            for planEx in day.strengthExercises {
                guard let exercise = planEx.exercise else { continue }
                for involvement in exercise.muscleInvolvements {
                    guard let muscleID = involvement.muscleGroupID else { continue }
                    let effective = Double(planEx.targetSets) * involvement.involvementScore
                    childVolumes[muscleID, default: 0] += effective
                }
            }
        }

        // Resolve each muscle ID → (parentName, childName) and group
        var grouped: [String: [(name: String, sets: Double)]] = [:]

        for (muscleID, vol) in childVolumes {
            let resolved = resolveMuscleNames(muscleID)
            grouped[resolved.parent, default: []].append((name: resolved.child, sets: vol))
        }

        // Sort children by volume desc, parents alphabetically
        return grouped
            .map { (parent: $0.key, children: $0.value.sorted { $0.sets > $1.sets }) }
            .sorted { $0.parent < $1.parent }
    }

    /// Volume status (green/yellow/red) for a muscle given its weekly effective sets.
    func volumeStatus(muscle: String, effectiveSets: Double) -> VolumeStatus {
        let benchmarks = fetchMuscleBenchmarks(name: muscle)
        if effectiveSets < Double(benchmarks.mev) { return .belowMEV }
        if effectiveSets > Double(benchmarks.mrv) { return .aboveMRV }
        if effectiveSets >= Double(benchmarks.mav) { return .inMAV }
        return .nearMEV
    }

    /// Junk volume alerts: any day × muscle combo exceeding MRV.
    func junkVolumeAlerts(for plan: WorkoutPlan) -> [JunkVolumeAlert] {
        var alerts: [JunkVolumeAlert] = []
        for day in plan.days where !day.isRest {
            let dayVolume = effectiveSetsPerMuscle(for: day)
            for (muscle, vol) in dayVolume {
                let benchmarks = fetchMuscleBenchmarks(name: muscle)
                if vol > Double(benchmarks.mrv) {
                    alerts.append(JunkVolumeAlert(
                        dayLabel: day.dayLabel,
                        weekday: day.weekday,
                        muscle: muscle,
                        effectiveSets: vol,
                        mrv: benchmarks.mrv
                    ))
                }
            }
        }
        return alerts
    }

    // MARK: - Color Linking

    /// Propagates exercise changes to all days with the same colorGroup.
    func propagateLinkedDays(from sourceDay: WorkoutPlanDay) {
        guard sourceDay.isLinked, let plan = sourceDay.plan else { return }
        let linkedDays = plan.days.filter {
            $0.id != sourceDay.id && $0.colorGroup == sourceDay.colorGroup
        }
        for targetDay in linkedDays {
            mirrorExercises(from: sourceDay, to: targetDay)
        }
        try? modelContext.save()
    }

    /// Links a day to a color group. Only allowed on empty days.
    func linkDay(_ day: WorkoutPlanDay, toGroup group: Int) -> Bool {
        guard !day.hasExercises else { return false }
        day.colorGroup = group
        try? modelContext.save()
        return true
    }

    /// Unlinks a day (sets colorGroup to -1).
    func unlinkDay(_ day: WorkoutPlanDay) {
        day.colorGroup = -1
        try? modelContext.save()
    }

    // MARK: - Today's Workout

    /// Returns today's plan days for active plans (strength + cardio).
    func todaysWorkout(on date: Date = Date()) -> [WorkoutPlanDay] {
        let weekday = date.weekdayISO
        var result: [WorkoutPlanDay] = []

        if let strengthPlan = fetchActivePlan(type: .strength) {
            result += strengthPlan.days.filter { $0.weekday == weekday && !$0.isRest }
        }
        if let cardioPlan = fetchActivePlan(type: .cardio) {
            result += cardioPlan.days.filter { $0.weekday == weekday && !$0.isRest }
        }

        return result
    }

    // MARK: - Private Helpers

    private func findOrCreateContainer(for plan: WorkoutPlan) -> Activity {
        // Check if container already set
        if let containerID = plan.containerActivityID {
            let descriptor = FetchDescriptor<Activity>(
                predicate: #Predicate { $0.id == containerID }
            )
            if let existing = try? modelContext.fetch(descriptor).first {
                return existing
            }
        }

        // Look for existing container by name convention
        let containerName = plan.planType == .strength ? "Strength Training" : "Cardio"
        let descriptor = FetchDescriptor<Activity>(
            predicate: #Predicate { $0.name == containerName && $0.typeRaw == "container" }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            plan.containerActivityID = existing.id
            return existing
        }

        // Create new container activity
        let icon = plan.planType == .strength ? "dumbbell.fill" : "figure.run"
        let container = Activity(name: containerName, icon: icon, type: .container)
        container.isManagedByWorkout = true
        modelContext.insert(container)
        plan.containerActivityID = container.id
        return container
    }

    private func findOrCreateShell(plan: WorkoutPlan, label: String, container: Activity) -> Activity {
        let shellName = "\(plan.name) – \(label)"

        // Find existing shell by name
        let descriptor = FetchDescriptor<Activity>(
            predicate: #Predicate { $0.name == shellName && $0.isManagedByWorkout == true }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.stoppedAt = nil // Re-activate if was stopped
            return existing
        }

        let shellIcon = plan.planType == .strength ? "dumbbell.fill" : "figure.run"
        let shell = Activity(name: shellName, icon: shellIcon, type: .checkbox)
        shell.isManagedByWorkout = true
        shell.parent = container
        modelContext.insert(shell)
        return shell
    }

    private func updateShellSchedule(_ shell: Activity, weekdays: [Int]) {
        shell.schedule = .weekly(weekdays)
        shell.timeWindow = nil  // All Day section
    }

    private func fetchShells(for plan: WorkoutPlan) -> [Activity] {
        let prefix = "\(plan.name) – "
        let descriptor = FetchDescriptor<Activity>(
            predicate: #Predicate { $0.isManagedByWorkout == true }
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.filter { $0.name.hasPrefix(prefix) }
    }

    private func mirrorExercises(from source: WorkoutPlanDay, to target: WorkoutPlanDay) {
        // Clear target
        for ex in target.strengthExercises { modelContext.delete(ex) }
        for ex in target.cardioExercises { modelContext.delete(ex) }

        // Copy strength exercises
        for srcEx in source.sortedStrengthExercises {
            let copy = StrengthPlanExercise(
                exercise: srcEx.exercise!,
                targetSets: srcEx.targetSets,
                rir: srcEx.rir,
                sortOrder: srcEx.sortOrder
            )
            copy.supersetGroup = srcEx.supersetGroup
            copy.planDay = target
            modelContext.insert(copy)
        }

        // Copy cardio exercises
        for srcEx in source.sortedCardioExercises {
            let copy = CardioPlanExercise(
                exercise: srcEx.exercise!,
                sessionType: srcEx.sessionType,
                sortOrder: srcEx.sortOrder
            )
            copy.targetDistance = srcEx.targetDistance
            copy.targetDurationMin = srcEx.targetDurationMin
            copy.sessionParamsData = srcEx.sessionParamsData
            copy.planDay = target
            modelContext.insert(copy)
        }

        // Sync labels
        target.dayLabel = source.dayLabel
        target.isLabelOverridden = source.isLabelOverridden
        target.isRest = source.isRest
    }

    private func resolveMuscleParentName(_ muscleID: UUID) -> String {
        let descriptor = FetchDescriptor<MuscleGroup>(
            predicate: #Predicate { $0.id == muscleID }
        )
        guard let muscle = try? modelContext.fetch(descriptor).first else { return "Unknown" }

        // If this is a child, recurse to parent
        if let parentID = muscle.parentID {
            return resolveMuscleParentName(parentID)
        }
        return muscle.name
    }

    /// Returns (parent, child) for any muscle ID. If it's already a parent, child == parent name.
    private func resolveMuscleNames(_ muscleID: UUID) -> (parent: String, child: String) {
        let descriptor = FetchDescriptor<MuscleGroup>(
            predicate: #Predicate { $0.id == muscleID }
        )
        guard let muscle = try? modelContext.fetch(descriptor).first else {
            return (parent: "Unknown", child: "Unknown")
        }

        if let parentID = muscle.parentID {
            return (parent: resolveMuscleParentName(parentID), child: muscle.name)
        }
        return (parent: muscle.name, child: muscle.name)
    }

    private func fetchMuscleBenchmarks(name: String) -> (mev: Int, mav: Int, mrv: Int) {
        let descriptor = FetchDescriptor<MuscleGroup>(
            predicate: #Predicate { $0.name == name }
        )
        guard let muscle = try? modelContext.fetch(descriptor).first else {
            return (mev: 8, mav: 16, mrv: 22) // Safe defaults
        }
        return (mev: muscle.mevSets, mav: muscle.mavSets, mrv: muscle.mrvSets)
    }

    /// Public accessor for advanced volume view
    func fetchMuscleBenchmarksPublic(name: String) -> (mev: Int, mav: Int, mrv: Int) {
        fetchMuscleBenchmarks(name: name)
    }
}

// MARK: - Supporting Types

enum VolumeStatus {
    case belowMEV   // 🔴 Not enough
    case nearMEV    // 🟡 Close but could be more
    case inMAV      // 🟢 Optimal
    case aboveMRV   // 🔴 Too much (junk volume risk)

    var color: String {
        switch self {
        case .belowMEV: return "red"
        case .nearMEV: return "yellow"
        case .inMAV: return "green"
        case .aboveMRV: return "red"
        }
    }

    var icon: String {
        switch self {
        case .belowMEV: return "🔴"
        case .nearMEV: return "🟡"
        case .inMAV: return "🟢"
        case .aboveMRV: return "🔴"
        }
    }
}

struct JunkVolumeAlert: Identifiable {
    let id = UUID()
    let dayLabel: String
    let weekday: Int
    let muscle: String
    let effectiveSets: Double
    let mrv: Int
}
