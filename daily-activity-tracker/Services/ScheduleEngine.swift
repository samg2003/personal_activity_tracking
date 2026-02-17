import Foundation

/// Determines which activities should appear on a given date.
protocol ScheduleEngineProtocol {
    func shouldShow(_ activity: Activity, on date: Date) -> Bool
    func activitiesForToday(from activities: [Activity], on date: Date, vacationDays: [VacationDay]) -> [Activity]
    func activitiesForToday(from activities: [Activity], on date: Date, vacationDays: [VacationDay], logs: [ActivityLog]) -> [Activity]
    func carriedForwardDate(for activity: Activity, on date: Date, logs: [ActivityLog]) -> Date?
    func carriedForwardSlots(for activity: Activity, on date: Date, logs: [ActivityLog]) -> (date: Date, slots: [TimeSlot])?
    func applicableChildren(for container: Activity, on date: Date, allActivities: [Activity], logs: [ActivityLog]) -> [Activity]
    func completionStatus(on date: Date, activities: [Activity], allActivities: [Activity], logs: [ActivityLog], vacationDays: [VacationDay]) -> DayCompletionStatus
    func isContainerCompleted(_ container: Activity, on day: Date, allActivities: [Activity], logs: [ActivityLog]) -> Bool
    func completionRate(for activity: Activity, days: Int, logs: [ActivityLog], vacationDays: [VacationDay], allActivities: [Activity]) -> Double
    func currentStreak(for activity: Activity, logs: [ActivityLog], allActivities: [Activity], vacationDays: [VacationDay]) -> Int
    func longestStreak(for activity: Activity, logs: [ActivityLog], allActivities: [Activity], vacationDays: [VacationDay]) -> Int
}

final class ScheduleEngine: ScheduleEngineProtocol {

    func shouldShow(_ activity: Activity, on date: Date) -> Bool {
        // Archived activities: only show on historical dates before they were stopped
        if activity.isArchived {
            guard let stopped = activity.stoppedAt,
                  date.startOfDay <= stopped else { return false }
        }
        // Don't show activities before they were created
        if date.startOfDay < activity.createdDate.startOfDay { return false }
        // Stopped activities don't appear after their stop date
        if let stopped = activity.stoppedAt, date.startOfDay > stopped { return false }

        // Use version-appropriate schedule (snapshot for historical dates)
        let schedule = activity.scheduleActive(on: date)
        switch schedule.type {
        case .sticky:
            let completedCount = activity.logs.filter { $0.status == .completed }.count
            return completedCount < activity.sessionsPerDay(on: date)
        case .adhoc:
            guard let specificDate = schedule.specificDate else { return false }
            return date.isSameDay(as: specificDate)
        default:
            return schedule.isScheduled(on: date)
        }
    }

    // MARK: - Carry-Forward for Missed Metrics

    /// Checks if a metric activity has a missed scheduled occurrence that should carry forward to `date`.
    /// Returns true if the most recent scheduled day before `date` has no completed/skipped log.
    private func shouldCarryForward(_ activity: Activity, on date: Date, logs: [ActivityLog]) -> Bool {
        guard !activity.isArchived else { return false }
        guard activity.type == .metric else { return false }
        let schedule = activity.scheduleActive(on: date)
        guard schedule.type == .weekly || schedule.type == .monthly else { return false }
        if shouldShow(activity, on: date) { return false }
        return carriedForwardDate(for: activity, on: date, logs: logs) != nil
    }

    /// Returns the original scheduled date that is being carried forward, or nil if nothing is overdue.
    /// Returns nil when the activity is normally scheduled today — each occurrence is independent.
    func carriedForwardDate(for activity: Activity, on date: Date, logs: [ActivityLog]) -> Date? {
        carriedForwardSlots(for: activity, on: date, logs: logs)?.date
    }

    /// Returns the original scheduled date AND which specific slots are overdue, or nil.
    /// For multi-session: only slots not completed/skipped on the original date (or today) carry forward.
    /// For single-session: returns the activity's slot if it's overdue.
    func carriedForwardSlots(for activity: Activity, on date: Date, logs: [ActivityLog]) -> (date: Date, slots: [TimeSlot])? {
        guard activity.type == .metric else { return nil }
        let schedule = activity.scheduleActive(on: date)
        guard schedule.type == .weekly || schedule.type == .monthly else { return nil }

        // If the activity is scheduled today, this is a fresh occurrence — no carry-forward
        if shouldShow(activity, on: date) { return nil }

        let calendar = Calendar.current
        let today = date.startOfDay

        for dayOffset in 1...60 {
            guard let checkDate = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }

            if checkDate.startOfDay < activity.createdDate.startOfDay { break }
            if let stopped = activity.stoppedAt, checkDate.startOfDay > stopped { continue }

            let historicalSchedule = activity.scheduleActive(on: checkDate)
            guard historicalSchedule.isScheduled(on: checkDate) else { continue }

            // Found most recent scheduled day — check per-slot
            let activityLogs = logs.filter { $0.activity?.id == activity.id }
            let relevantLogs = activityLogs.filter {
                calendar.isDate($0.date, inSameDayAs: checkDate) || calendar.isDate($0.date, inSameDayAs: date)
            }

            if activity.isMultiSession {
                // Per-slot: find slots that are neither completed nor skipped
                let historicalSlots = activity.timeSlotsActive(on: checkDate)
                let overdueSlots = historicalSlots.filter { slot in
                    let completed = relevantLogs.contains { $0.status == .completed && $0.timeSlot == slot }
                    let skipped = relevantLogs.contains { $0.status == .skipped && $0.timeSlot == slot }
                    return !completed && !skipped
                }
                return overdueSlots.isEmpty ? nil : (checkDate.startOfDay, overdueSlots)
            } else {
                // Single-session: same logic as before
                let completedCount = relevantLogs.filter { $0.status == .completed }.count
                let hasSkip = relevantLogs.contains { $0.status == .skipped }
                let sessions = activity.sessionsPerDay(on: checkDate)
                let done = completedCount >= sessions || (hasSkip && completedCount == 0)
                if done { return nil }
                let slot = activity.timeWindow?.slot ?? .morning
                return (checkDate.startOfDay, [slot])
            }
        }

        return nil
    }

    // MARK: - Container Applicable Children

    /// All children of a container that should appear on `date`: normally scheduled + carry-forward.
    /// This is the single source of truth for "which children does this container have today?"
    func applicableChildren(for container: Activity, on date: Date, allActivities: [Activity], logs: [ActivityLog]) -> [Activity] {
        let allChildren = container.historicalChildren(on: date, from: allActivities)
        let scheduled = allChildren.filter { child in
            if date < child.createdDate.startOfDay { return false }
            if let stopped = child.stoppedAt, date > stopped { return false }
            return child.scheduleActive(on: date).isScheduled(on: date)
        }
        let scheduledIDs = Set(scheduled.map { $0.id })
        let carryForward = allChildren.filter { child in
            !scheduledIDs.contains(child.id)
            && !child.isArchived
            && carriedForwardDate(for: child, on: date, logs: logs) != nil
        }
        return (scheduled + carryForward).sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Activities for Today

    /// Legacy method without logs (no carry-forward)
    func activitiesForToday(from activities: [Activity], on date: Date, vacationDays: [VacationDay]) -> [Activity] {
        return activities
            .filter { $0.parent == nil && $0.parentID(on: date) == nil }
            .filter { shouldShow($0, on: date) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Full method with carry-forward support
    func activitiesForToday(from activities: [Activity], on date: Date, vacationDays: [VacationDay], logs: [ActivityLog]) -> [Activity] {
        let topLevel = activities.filter { $0.parent == nil && $0.parentID(on: date) == nil }

        // Normal scheduled activities
        var result = topLevel
            .filter { shouldShow($0, on: date) }

        // Add carry-forward metrics (avoid duplicates)
        let resultIDs = Set(result.map { $0.id })
        let carryForward = topLevel.filter { activity in
            !resultIDs.contains(activity.id) && shouldCarryForward(activity, on: date, logs: logs)
        }
        result.append(contentsOf: carryForward)

        return result.sorted { $0.sortOrder < $1.sortOrder }
    }
}

// MARK: - Centralized Day Completion

/// Single source of truth for a day's completion status — used by DatePickerBar, HeatmapView, etc.
struct DayCompletionStatus {
    /// Completion rate 0…1. Negative means no scheduled activities.
    let rate: Double
    /// True when every scheduled activity is skipped (and at least one exists)
    let allSkipped: Bool

    static let noData = DayCompletionStatus(rate: -1, allSkipped: false)
    static let skipped = DayCompletionStatus(rate: 0, allSkipped: true)
}

extension ScheduleEngine {

    /// Compute completion status for a single day.
    /// `activities` — the activities to evaluate (may be a single activity for per-activity heatmaps).
    /// `allActivities` — full activity list for resolving container children and scheduling.
    func completionStatus(
        on date: Date,
        activities: [Activity],
        allActivities: [Activity],
        logs: [ActivityLog],
        vacationDays: [VacationDay]
    ) -> DayCompletionStatus {
        if date.startOfDay > Date().startOfDay { return .noData }

        // Determine what's scheduled. For single-activity heatmaps, bypass
        // activitiesForToday (which filters parent==nil) and check schedule directly.
        let scheduled: [Activity]
        if activities.count == 1, let activity = activities.first {
            // Single-activity mode: check if this activity should show on this date
            guard shouldShow(activity, on: date) else { return .noData }
            scheduled = [activity]
        } else {
            scheduled = activitiesForToday(from: activities, on: date, vacationDays: vacationDays)
            guard !scheduled.isEmpty else { return .noData }
        }

        let dayLogs = logs.filter { $0.date.isSameDay(as: date) }
        var total = 0.0
        var done = 0.0
        var skippedCount = 0

        for activity in scheduled {
            let actLogs = dayLogs.filter { $0.activity?.id == activity.id }

            if activity.type == .container {
                let children = applicableChildren(for: activity, on: date, allActivities: allActivities, logs: logs)
                for child in children {
                    processActivitySlots(child, on: date, logs: dayLogs, total: &total, done: &done, skippedCount: &skippedCount)
                }
            } else if activity.type == .cumulative && (activity.targetValue == nil || activity.targetValue == 0) {
                let actSkipped = actLogs.contains { $0.status == .skipped }
                if actSkipped { skippedCount += 1 }
            } else {
                processActivitySlots(activity, on: date, logs: dayLogs, total: &total, done: &done, skippedCount: &skippedCount)
            }
        }

        if total <= 0 && skippedCount > 0 { return .skipped }
        guard total > 0 else { return .noData }
        return DayCompletionStatus(rate: done / total, allSkipped: false)
    }

    /// Shared logic for processing an activity's completion/skip slots.
    /// Handles both multi-session (per-slot) and single-session activities.
    private func processActivitySlots(
        _ activity: Activity,
        on date: Date,
        logs dayLogs: [ActivityLog],
        total: inout Double,
        done: inout Double,
        skippedCount: inout Int
    ) {
        let actLogs = dayLogs.filter { $0.activity?.id == activity.id }
        let slots = activity.timeSlotsActive(on: date)
        let sessions = activity.sessionsPerDay(on: date)

        if slots.count > 1 {
            // Multi-session: per-slot counting
            var slotsDone = 0
            var slotsSkipped = 0
            for slot in slots {
                if actLogs.contains(where: { $0.status == .completed && $0.timeSlot == slot }) {
                    slotsDone += 1
                } else if actLogs.contains(where: { $0.status == .skipped && $0.timeSlot == slot }) {
                    slotsSkipped += 1
                }
            }
            if slotsSkipped == sessions && slotsDone == 0 { skippedCount += 1; return }
            total += Double(sessions - slotsSkipped)
            done += Double(min(slotsDone, sessions - slotsSkipped))
        } else {
            // Single-session
            let actSkipped = actLogs.contains { $0.status == .skipped }
            if actSkipped && !actLogs.contains(where: { $0.status == .completed }) {
                skippedCount += 1
            } else if activity.type == .cumulative, let target = activity.targetValue, target > 0 {
                total += 1.0
                let values = actLogs.filter { $0.status == .completed }.compactMap(\.value)
                let cumVal = activity.aggregateDayValue(from: values)
                done += min(cumVal / target, 1.0)
            } else {
                total += Double(sessions)
                let completedCount = Double(actLogs.filter { $0.status == .completed }.count)
                done += min(completedCount, Double(sessions))
            }
        }
    }
}

// MARK: - Container Completion

extension ScheduleEngine {

    /// Whether all applicable children of a container are completed on a given day
    func isContainerCompleted(_ container: Activity, on day: Date, allActivities: [Activity], logs: [ActivityLog]) -> Bool {
        let children = applicableChildren(for: container, on: day, allActivities: allActivities, logs: logs)
        guard !children.isEmpty else { return false }
        return children.allSatisfy { child in
            let childLogs = logs.filter { $0.activity?.id == child.id && $0.date.isSameDay(as: day) }
            // Skipped children don't block completion
            let isSkipped = childLogs.contains { $0.status == .skipped } && !childLogs.contains { $0.status == .completed }
            if isSkipped { return true }
            let completed = childLogs.filter { $0.status == .completed }.count
            return completed >= child.sessionsPerDay(on: day)
        }
    }
}

// MARK: - Completion Rate (Multi-day)

extension ScheduleEngine {

    /// Completion rate for an activity over a given number of past days.
    /// Handles containers (all-children-done fraction), regular activities (schedule-aware, skip-excluded, multi-session).
    func completionRate(
        for activity: Activity,
        days: Int,
        logs: [ActivityLog],
        vacationDays: [VacationDay],
        allActivities: [Activity]
    ) -> Double {
        let calendar = Calendar.current
        let today = Date().startOfDay
        let vacationSet = Set(vacationDays.map { $0.date.startOfDay })

        if activity.type == .container {
            return containerCompletionRate(for: activity, days: days, logs: logs, vacationSet: vacationSet, allActivities: allActivities)
        }

        let activityLogs = logs.filter { $0.activity?.id == activity.id }
        var totalExpected = 0
        var totalCompleted = 0

        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if vacationSet.contains(day) { continue }
            if let stopped = activity.stoppedAt, day > stopped { continue }
            if day < activity.createdDate.startOfDay { continue }

            let schedule = activity.scheduleActive(on: day)
            guard schedule.isScheduled(on: day) else { continue }

            let dayActivityLogs = activityLogs.filter { $0.date.startOfDay == day }
            let slots = activity.timeSlotsActive(on: day)
            let sessions = activity.sessionsPerDay(on: day)

            if slots.count > 1 {
                var slotsDone = 0
                var slotsSkipped = 0
                for slot in slots {
                    if dayActivityLogs.contains(where: { $0.status == .completed && $0.timeSlot == slot }) {
                        slotsDone += 1
                    } else if dayActivityLogs.contains(where: { $0.status == .skipped && $0.timeSlot == slot }) {
                        slotsSkipped += 1
                    }
                }
                if slotsSkipped == sessions && slotsDone == 0 { continue }
                totalExpected += sessions - slotsSkipped
                totalCompleted += min(slotsDone, sessions - slotsSkipped)
            } else {
                let dayCompleted = dayActivityLogs.filter { $0.status == .completed }.count
                let daySkipped = dayActivityLogs.contains { $0.status == .skipped }
                if daySkipped && dayCompleted == 0 { continue }
                totalExpected += sessions
                totalCompleted += min(dayCompleted, sessions)
            }
        }

        guard totalExpected > 0 else { return 0 }
        return Double(totalCompleted) / Double(totalExpected)
    }

    private func containerCompletionRate(
        for container: Activity,
        days: Int,
        logs: [ActivityLog],
        vacationSet: Set<Date>,
        allActivities: [Activity]
    ) -> Double {
        let calendar = Calendar.current
        let today = Date().startOfDay
        var totalWeight = 0.0
        var completedWeight = 0.0

        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if vacationSet.contains(day) { continue }
            if let stopped = container.stoppedAt, day > stopped { continue }
            if day < container.createdDate.startOfDay { continue }

            let schedule = container.scheduleActive(on: day)
            guard schedule.isScheduled(on: day) else { continue }

            let scheduledChildren = applicableChildren(for: container, on: day, allActivities: allActivities, logs: logs)
            guard !scheduledChildren.isEmpty else { continue }

            // Per-child fractional scoring, excluding skipped items
            var dayExpected = 0.0
            var dayCompleted = 0.0

            for child in scheduledChildren {
                let childLogs = logs.filter { $0.activity?.id == child.id && $0.date.isSameDay(as: day) }
                let slots = child.timeSlotsActive(on: day)
                let sessions = child.sessionsPerDay(on: day)

                if slots.count > 1 {
                    // Multi-session child
                    var slotsDone = 0
                    var slotsSkipped = 0
                    for slot in slots {
                        if childLogs.contains(where: { $0.status == .completed && $0.timeSlot == slot }) {
                            slotsDone += 1
                        } else if childLogs.contains(where: { $0.status == .skipped && $0.timeSlot == slot }) {
                            slotsSkipped += 1
                        }
                    }
                    // All sessions skipped with none completed → exclude child
                    if slotsSkipped == sessions && slotsDone == 0 { continue }
                    dayExpected += Double(sessions - slotsSkipped)
                    dayCompleted += Double(min(slotsDone, sessions - slotsSkipped))
                } else {
                    // Single-session child
                    let completed = childLogs.filter { $0.status == .completed }.count
                    let skipped = childLogs.contains { $0.status == .skipped }
                    if skipped && completed == 0 { continue }
                    dayExpected += Double(sessions)
                    dayCompleted += Double(min(completed, sessions))
                }
            }

            // All children skipped → exclude day
            guard dayExpected > 0 else { continue }
            totalWeight += 1.0
            completedWeight += dayCompleted / dayExpected
        }

        guard totalWeight > 0 else { return 0 }
        return completedWeight / totalWeight
    }
}

// MARK: - Streaks

extension ScheduleEngine {

    /// Current consecutive streak for an activity (schedule-aware, vacation/skip pass-through)
    func currentStreak(
        for activity: Activity,
        logs: [ActivityLog],
        allActivities: [Activity],
        vacationDays: [VacationDay]
    ) -> Int {
        let calendar = Calendar.current
        let vacationSet = Set(vacationDays.map { $0.date.startOfDay })

        if activity.type == .container {
            return containerStreak(for: activity, mode: .current, logs: logs, allActivities: allActivities, vacationSet: vacationSet)
        }

        let activityLogs = logs.filter { $0.activity?.id == activity.id }

        var streak = 0
        var day = Date().startOfDay
        if !isActivityDayCompleted(activityLogs: activityLogs, activity: activity, day: day) {
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = prev
        }

        for _ in 0..<3650 {
            if day < activity.createdDate.startOfDay { break }
            if let stopped = activity.stoppedAt, day > stopped { break }

            let schedule = activity.scheduleActive(on: day)
            if !schedule.isScheduled(on: day) {
                // not scheduled — pass through
            } else if isActivityDayCompleted(activityLogs: activityLogs, activity: activity, day: day) {
                streak += 1
            } else if vacationSet.contains(day) {
                // vacation — pass through
            } else if isActivityDayFullySkipped(activityLogs: activityLogs, day: day) {
                // all sessions skipped, none completed — pass through
            } else {
                break
            }

            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    /// Longest-ever streak for an activity
    func longestStreak(
        for activity: Activity,
        logs: [ActivityLog],
        allActivities: [Activity],
        vacationDays: [VacationDay]
    ) -> Int {
        let calendar = Calendar.current
        let vacationSet = Set(vacationDays.map { $0.date.startOfDay })

        if activity.type == .container {
            return containerStreak(for: activity, mode: .longest, logs: logs, allActivities: allActivities, vacationSet: vacationSet)
        }

        let activityLogs = logs.filter { $0.activity?.id == activity.id }
        guard let earliest = activity.createdAt ?? activityLogs.map(\.date).min() else { return 0 }

        var maxStreak = 0
        var current = 0
        var day = Date().startOfDay

        while day >= earliest.startOfDay {
            if day < activity.createdDate.startOfDay { break }
            if let stopped = activity.stoppedAt, day > stopped { break }

            let schedule = activity.scheduleActive(on: day)
            if !schedule.isScheduled(on: day) || vacationSet.contains(day) {
                // not scheduled or vacation — pass through
            } else if isActivityDayCompleted(activityLogs: activityLogs, activity: activity, day: day) {
                current += 1
                maxStreak = max(maxStreak, current)
            } else if isActivityDayFullySkipped(activityLogs: activityLogs, day: day) {
                // all sessions skipped, none completed — pass through
            } else {
                current = 0
            }

            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return maxStreak
    }

    // MARK: - Container Streak (shared between current/longest)

    private enum StreakMode { case current, longest }

    private func containerStreak(
        for container: Activity,
        mode: StreakMode,
        logs: [ActivityLog],
        allActivities: [Activity],
        vacationSet: Set<Date>
    ) -> Int {
        let calendar = Calendar.current

        var day = Date().startOfDay

        switch mode {
        case .current:
            if !isContainerCompleted(container, on: day, allActivities: allActivities, logs: logs) {
                guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
                day = prev
            }
            var streak = 0
            for _ in 0..<3650 {
                if day < container.createdDate.startOfDay { break }
                if let stopped = container.stoppedAt, day > stopped { break }
                let schedule = container.scheduleActive(on: day)
                if !schedule.isScheduled(on: day) {
                    // pass through
                } else if isContainerCompleted(container, on: day, allActivities: allActivities, logs: logs) {
                    streak += 1
                } else if vacationSet.contains(day) {
                    // pass through
                } else if isContainerDayFullySkipped(container, on: day, allActivities: allActivities, logs: logs) {
                    // all children skipped, none completed — pass through
                } else {
                    break
                }
                guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
                day = prev
            }
            return streak

        case .longest:
            let childIDs = Set(container.historicalChildren(on: Date().startOfDay, from: allActivities).map { $0.id })
            guard let earliest = container.createdAt ?? logs.filter({ childIDs.contains($0.activity?.id ?? UUID()) }).map(\.date).min() else { return 0 }
            var maxStreak = 0
            var current = 0
            while day >= earliest.startOfDay {
                if day < container.createdDate.startOfDay { break }
                let schedule = container.scheduleActive(on: day)
                if !schedule.isScheduled(on: day) || vacationSet.contains(day) {
                    // pass through
                } else if isContainerCompleted(container, on: day, allActivities: allActivities, logs: logs) {
                    current += 1
                    maxStreak = max(maxStreak, current)
                } else if isContainerDayFullySkipped(container, on: day, allActivities: allActivities, logs: logs) {
                    // all children skipped, none completed — pass through
                } else {
                    current = 0
                }
                guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
                day = prev
            }
            return maxStreak
        }
    }

    /// Whether all scheduled children of a container are fully skipped (no completions) on a given day
    private func isContainerDayFullySkipped(_ container: Activity, on day: Date, allActivities: [Activity], logs: [ActivityLog]) -> Bool {
        let children = applicableChildren(for: container, on: day, allActivities: allActivities, logs: logs)
        guard !children.isEmpty else { return false }
        let allSkipped = children.allSatisfy { child in
            logs.contains { $0.activity?.id == child.id && $0.status == .skipped && $0.date.isSameDay(as: day) }
        }
        let anyCompleted = children.contains { child in
            logs.contains { $0.activity?.id == child.id && $0.status == .completed && $0.date.isSameDay(as: day) }
        }
        return allSkipped && !anyCompleted
    }

    /// Whether all sessions for a non-container activity are completed on a given day
    private func isActivityDayCompleted(activityLogs: [ActivityLog], activity: Activity, day: Date) -> Bool {
        let completed = activityLogs.filter { $0.status == .completed && $0.date.startOfDay == day }.count
        return completed >= activity.sessionsPerDay(on: day)
    }

    /// Whether a day is fully skipped (has skip logs but no completions)
    private func isActivityDayFullySkipped(activityLogs: [ActivityLog], day: Date) -> Bool {
        let dayLogs = activityLogs.filter { $0.date.startOfDay == day }
        let hasSkip = dayLogs.contains { $0.status == .skipped }
        let hasCompletion = dayLogs.contains { $0.status == .completed }
        return hasSkip && !hasCompletion
    }
}
