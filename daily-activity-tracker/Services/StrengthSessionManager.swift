import Foundation
import SwiftData

/// Manages strength workout session lifecycle: start, pause, resume, log sets, finish, abandon.
/// Bridges to the activity system via auto-completion of shell activities.
final class StrengthSessionManager {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Session Lifecycle

    /// Starts a new strength session for the given plan day.
    @discardableResult
    func startSession(for planDay: WorkoutPlanDay) -> StrengthSession {
        let plan = planDay.plan
        let session = StrengthSession(
            planName: plan?.name ?? "Workout",
            dayLabel: planDay.dayLabel,
            weekday: planDay.weekday,
            planDay: planDay
        )
        modelContext.insert(session)
        try? modelContext.save()
        return session
    }

    /// Pauses the active session, recording the pause timestamp.
    func pauseSession(_ session: StrengthSession) {
        guard session.status == .inProgress else { return }
        session.pausedAt = Date()
        session.status = .paused
        try? modelContext.save()
    }

    /// Resumes a paused session, accumulating paused duration.
    func resumeSession(_ session: StrengthSession) {
        guard session.status == .paused, let pausedAt = session.pausedAt else { return }
        session.totalPausedSeconds += Date().timeIntervalSince(pausedAt)
        session.pausedAt = nil
        session.status = .inProgress
        try? modelContext.save()
    }

    /// Logs a working or warmup set for an exercise within the session.
    @discardableResult
    func logSet(
        session: StrengthSession,
        exercise: Exercise,
        reps: Int,
        weight: Double,
        isWarmup: Bool = false,
        durationSeconds: Int? = nil
    ) -> WorkoutSetLog {
        // Determine set number: count existing non-warmup sets for this exercise + 1
        let existingCount = session.setLogs.filter {
            $0.exercise?.id == exercise.id && $0.isWarmup == isWarmup
        }.count

        let setLog = WorkoutSetLog(
            exercise: exercise,
            setNumber: existingCount + 1,
            reps: reps,
            weight: weight,
            isWarmup: isWarmup
        )
        setLog.durationSeconds = durationSeconds
        setLog.session = session
        modelContext.insert(setLog)
        try? modelContext.save()
        return setLog
    }

    /// Deletes a previously logged set.
    func deleteSet(_ setLog: WorkoutSetLog) {
        modelContext.delete(setLog)
        try? modelContext.save()
    }

    /// Updates an existing set log in place.
    func updateSet(_ setLog: WorkoutSetLog, reps: Int, weight: Double, isWarmup: Bool) {
        setLog.reps = reps
        setLog.weight = weight
        setLog.isWarmup = isWarmup
        try? modelContext.save()
    }

    /// Finishes the session, computes completion, and creates an ActivityLog on the shell.
    func finishSession(_ session: StrengthSession) {
        // If paused, accumulate final pause
        if session.status == .paused, let pausedAt = session.pausedAt {
            session.totalPausedSeconds += Date().timeIntervalSince(pausedAt)
            session.pausedAt = nil
        }

        session.endedAt = Date()
        session.status = .completed

        // Auto-completion bridge
        autoCompleteShell(for: session)
        try? modelContext.save()
    }

    /// Marks session as abandoned. No ActivityLog created.
    /// If this was a resumed session, only removes sets added after the resume and reverts to completed.
    func abandonSession(_ session: StrengthSession) {
        if session.status == .paused, let pausedAt = session.pausedAt {
            session.totalPausedSeconds += Date().timeIntervalSince(pausedAt)
            session.pausedAt = nil
        }

        // If this was a resumed completed session, revert instead of full abandon
        if session.resumedAtSetCount >= 0 {
            let sortedSets = session.completedSets.sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
            let setsToRemove = sortedSets.dropFirst(session.resumedAtSetCount)
            for set in setsToRemove {
                modelContext.delete(set)
            }
            session.status = .completed
            // Restore original timing
            session.endedAt = session.resumedAtEndedAt ?? Date()
            if session.resumedAtPausedSeconds >= 0 {
                session.totalPausedSeconds = session.resumedAtPausedSeconds
            }
            session.resumedAtSetCount = -1
            session.resumedAtEndedAt = nil
            session.resumedAtPausedSeconds = -1
        } else {
            session.endedAt = Date()
            session.status = .abandoned
        }
        try? modelContext.save()
    }

    // MARK: - Auto-Fill

    /// Returns suggested (reps, weight) from the most recent session for the given exercise.
    /// Returns nil if no history exists.
    func autoFillSuggestion(for exercise: Exercise) -> (reps: Int, weight: Double)? {
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<WorkoutSetLog>(
            predicate: #Predicate {
                $0.isWarmup == false
            },
            sortBy: [SortDescriptor(\WorkoutSetLog.completedAt, order: .reverse)]
        )

        guard let allSets = try? modelContext.fetch(descriptor) else { return nil }

        // Find most recent set for this specific exercise
        guard let recentSet = allSets.first(where: { $0.exercise?.id == exerciseID }) else {
            return nil
        }

        return (reps: recentSet.reps, weight: recentSet.weight)
    }

    // MARK: - Active Session Detection (Recovery)

    /// Returns any in-progress or paused strength session (for recovery on app relaunch).
    func activeSession() -> StrengthSession? {
        let inProgressRaw = SessionStatus.inProgress.rawValue
        let pausedRaw = SessionStatus.paused.rawValue

        let descriptor = FetchDescriptor<StrengthSession>(
            predicate: #Predicate {
                $0.statusRaw == inProgressRaw || $0.statusRaw == pausedRaw
            },
            sortBy: [SortDescriptor(\StrengthSession.startedAt, order: .reverse)]
        )

        return try? modelContext.fetch(descriptor).first
    }

    /// Finds today's completed-but-incomplete session for a plan day (for "Continue Workout").
    func findIncompleteSession(for day: WorkoutPlanDay) -> StrengthSession? {
        let dayStart = Date().startOfDay
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        let dayID = day.id
        let completedRaw = SessionStatus.completed.rawValue

        let descriptor = FetchDescriptor<StrengthSession>(
            predicate: #Predicate {
                $0.planDay?.id == dayID &&
                $0.statusRaw == completedRaw &&
                $0.date >= dayStart && $0.date < dayEnd
            },
            sortBy: [SortDescriptor(\StrengthSession.startedAt, order: .reverse)]
        )

        guard let session = try? modelContext.fetch(descriptor).first else { return nil }

        // Only return if actually incomplete
        let completedSets = session.completedSets.count
        let plannedSets = day.totalSets
        guard plannedSets > 0, Double(completedSets) / Double(plannedSets) < 0.8 else { return nil }
        return session
    }

    /// Re-opens a completed session so the user can continue adding sets.
    /// Snapshots set count and timing so abandon can revert cleanly.
    /// Adds the gap since original completion to paused seconds so the timer only shows active workout time.
    func resumeCompletedSession(_ session: StrengthSession) {
        session.resumedAtSetCount = session.completedSets.count
        session.resumedAtEndedAt = session.endedAt
        session.resumedAtPausedSeconds = session.totalPausedSeconds

        // Account for the gap between original end and now as "paused" time
        if let endedAt = session.endedAt {
            session.totalPausedSeconds += Date().timeIntervalSince(endedAt)
        }

        session.status = .inProgress
        session.endedAt = nil
        session.pausedAt = nil
        try? modelContext.save()
    }

    // MARK: - Session Queries

    /// Returns completed sets grouped by exercise for display.
    func setsGroupedByExercise(for session: StrengthSession) -> [(exercise: Exercise, sets: [WorkoutSetLog])] {
        let grouped = Dictionary(grouping: session.setLogs) { $0.exercise?.id ?? UUID() }

        // Maintain exercise order from the plan day
        var orderedExercises: [Exercise] = []
        if let planDay = session.planDay {
            orderedExercises = planDay.sortedStrengthExercises.compactMap(\.exercise)
        }

        // Include any exercises logged that aren't in the plan (ad-hoc)
        let planExIDs = Set(orderedExercises.map(\.id))
        for setLog in session.setLogs {
            if let ex = setLog.exercise, !planExIDs.contains(ex.id) {
                orderedExercises.append(ex)
            }
        }

        return orderedExercises.compactMap { exercise in
            guard let sets = grouped[exercise.id], !sets.isEmpty else { return nil }
            let sorted = sets.sorted { $0.setNumber < $1.setNumber }
            return (exercise: exercise, sets: sorted)
        }
    }

    /// Completion ratio for a session (0.0 – 1.0+).
    func completionRatio(for session: StrengthSession) -> Double {
        let completedSets = session.completedSets.count
        let plannedSets = session.planDay?.totalSets ?? completedSets
        guard plannedSets > 0 else { return 1.0 }
        return Double(completedSets) / Double(plannedSets)
    }

    /// Total volume = sum(reps × weight) across all non-warmup sets.
    func totalVolume(for session: StrengthSession) -> Double {
        session.completedSets.reduce(0) { $0 + Double($1.reps) * $1.weight }
    }

    // MARK: - Auto-Completion Bridge


    /// Deletes a session and its associated shell ActivityLog (keeps dashboard in sync).
    func deleteSession(_ session: StrengthSession) {
        // Remove today's ActivityLog for the shell so dashboard unchecks
        if let shell = findShellActivity(for: session) {
            let shellID = shell.id
            let sessionDate = session.date.startOfDay
            let descriptor = FetchDescriptor<ActivityLog>(
                predicate: #Predicate { $0.activity?.id == shellID }
            )
            if let logs = try? modelContext.fetch(descriptor) {
                for log in logs where Calendar.current.isDate(log.date, inSameDayAs: sessionDate) {
                    modelContext.delete(log)
                }
            }
        }
        modelContext.delete(session)
        try? modelContext.save()
    }

    /// Creates an ActivityLog on the shell activity for auto-completion.
    private func autoCompleteShell(for session: StrengthSession) {
        guard let shellActivity = findShellActivity(for: session) else { return }

        let ratio = completionRatio(for: session)
        let today = Date().startOfDay

        // Check if log already exists for today
        let shellID = shellActivity.id
        let existingDescriptor = FetchDescriptor<ActivityLog>(
            predicate: #Predicate { $0.activity?.id == shellID }
        )
        if let existing = try? modelContext.fetch(existingDescriptor),
           existing.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
            return // Already logged today
        }

        // Only auto-complete the shell when the session meets the threshold.
        // Incomplete sessions stay pending — no log created.
        if ratio >= 0.8 {
            let log = ActivityLog(activity: shellActivity, date: today, status: .completed)
            modelContext.insert(log)
        }
    }

    /// Finds the shell activity that matches this session's plan + label.
    private func findShellActivity(for session: StrengthSession) -> Activity? {
        let shellName = "\(session.planName) – \(session.dayLabel)"
        let descriptor = FetchDescriptor<Activity>(
            predicate: #Predicate { $0.name == shellName && $0.isManagedByWorkout == true }
        )
        return try? modelContext.fetch(descriptor).first
    }
}
