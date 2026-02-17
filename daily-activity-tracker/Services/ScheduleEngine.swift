import Foundation

/// Determines which activities should appear on a given date.
protocol ScheduleEngineProtocol {
    func shouldShow(_ activity: Activity, on date: Date) -> Bool
    func activitiesForToday(from activities: [Activity], on date: Date, vacationDays: [VacationDay]) -> [Activity]
    func activitiesForToday(from activities: [Activity], on date: Date, vacationDays: [VacationDay], logs: [ActivityLog]) -> [Activity]
    func carriedForwardDate(for activity: Activity, on date: Date, logs: [ActivityLog]) -> Date?
    func completionStatus(on date: Date, activities: [Activity], logs: [ActivityLog], vacationDays: [VacationDay]) -> DayCompletionStatus
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
        guard activity.type == .checkbox || activity.type == .value || activity.type == .metric else { return false }
        let schedule = activity.scheduleActive(on: date)
        guard schedule.type == .weekly || schedule.type == .monthly else { return false }
        if shouldShow(activity, on: date) { return false }
        return carriedForwardDate(for: activity, on: date, logs: logs) != nil
    }

    /// Returns the original scheduled date that is being carried forward, or nil if nothing is overdue.
    /// Returns nil when the activity is normally scheduled today — each occurrence is independent.
    func carriedForwardDate(for activity: Activity, on date: Date, logs: [ActivityLog]) -> Date? {
        guard activity.type == .checkbox || activity.type == .value || activity.type == .metric else { return nil }
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

            // Use the schedule that was active on the historical day
            let historicalSchedule = activity.scheduleActive(on: checkDate)
            guard historicalSchedule.isScheduled(on: checkDate) else { continue }

            // Found most recent scheduled day — check if fully completed/skipped that day OR today
            let activityLogs = logs.filter { $0.activity?.id == activity.id }
            let checkDateLogs = activityLogs.filter {
                calendar.isDate($0.date, inSameDayAs: checkDate) || calendar.isDate($0.date, inSameDayAs: date)
            }
            let completedCount = checkDateLogs.filter { $0.status == .completed }.count
            let hasSkip = checkDateLogs.contains { $0.status == .skipped }
            let sessions = activity.sessionsPerDay(on: checkDate)
            let done = completedCount >= sessions || (hasSkip && completedCount == 0)

            return done ? nil : checkDate.startOfDay
        }

        return nil
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

    /// Compute completion status for a single day. Handles containers, cumulatives, multi-session, etc.
    func completionStatus(
        on date: Date,
        activities: [Activity],
        logs: [ActivityLog],
        vacationDays: [VacationDay]
    ) -> DayCompletionStatus {
        if date.startOfDay > Date().startOfDay { return .noData }
        let scheduled = activitiesForToday(from: activities, on: date, vacationDays: vacationDays)
        guard !scheduled.isEmpty else { return .noData }

        let dayLogs = logs.filter { $0.date.isSameDay(as: date) }
        var total = 0.0
        var done = 0.0
        var skippedCount = 0

        for activity in scheduled {
            let actLogs = dayLogs.filter { $0.activity?.id == activity.id }

            if activity.type == .container {
                let children = activity.historicalChildren(on: date, from: activities)
                    .filter { shouldShow($0, on: date) }
                for child in children {
                    let childLogs = dayLogs.filter { $0.activity?.id == child.id }
                    let sessions = child.sessionsPerDay(on: date)

                    if child.isMultiSession {
                        var slotsDone = 0
                        var slotsSkipped = 0
                        for slot in child.timeSlots {
                            if childLogs.contains(where: { $0.status == .completed && $0.timeSlot == slot }) {
                                slotsDone += 1
                            } else if childLogs.contains(where: { $0.status == .skipped && $0.timeSlot == slot }) {
                                slotsSkipped += 1
                            }
                        }
                        if slotsSkipped == sessions && slotsDone == 0 { skippedCount += 1; continue }
                        total += Double(sessions - slotsSkipped)
                        done += Double(min(slotsDone, sessions - slotsSkipped))
                    } else {
                        let childCompleted = childLogs.filter { $0.status == .completed }.count
                        let childHasSkip = childLogs.contains { $0.status == .skipped }
                        if childHasSkip && childCompleted == 0 { skippedCount += 1; continue }
                        total += Double(sessions)
                        done += min(Double(childCompleted), Double(sessions))
                    }
                }
            } else if activity.type == .cumulative && (activity.targetValue == nil || activity.targetValue == 0) {
                let actSkipped = actLogs.contains { $0.status == .skipped }
                if actSkipped { skippedCount += 1 }
            } else if activity.isMultiSession {
                // Per-slot skip handling: deduct skipped sessions from denominator
                let sessions = activity.sessionsPerDay(on: date)
                var slotsDone = 0
                var slotsSkipped = 0
                for slot in activity.timeSlots {
                    if actLogs.contains(where: { $0.status == .completed && $0.timeSlot == slot }) {
                        slotsDone += 1
                    } else if actLogs.contains(where: { $0.status == .skipped && $0.timeSlot == slot }) {
                        slotsSkipped += 1
                    }
                }
                if slotsSkipped == sessions && slotsDone == 0 { skippedCount += 1; continue }
                total += Double(sessions - slotsSkipped)
                done += Double(min(slotsDone, sessions - slotsSkipped))
            } else {
                let actSkipped = actLogs.contains { $0.status == .skipped }
                if actSkipped {
                    skippedCount += 1
                } else if activity.type == .cumulative, let target = activity.targetValue, target > 0 {
                    total += 1.0
                    let values = actLogs
                        .filter { $0.status == .completed }
                        .compactMap(\.value)
                    let cumVal = activity.aggregateDayValue(from: values)
                    done += min(cumVal / target, 1.0)
                } else {
                    let sessions = Double(activity.sessionsPerDay(on: date))
                    total += sessions
                    let completedCount = Double(actLogs.filter { $0.status == .completed }.count)
                    done += min(completedCount, sessions)
                }
            }
        }

        if total <= 0 && skippedCount > 0 { return .skipped }
        guard total > 0 else { return .noData }
        return DayCompletionStatus(rate: done / total, allSkipped: false)
    }
}

// MARK: - Container Completion

extension ScheduleEngine {

    /// Whether all children of a container are completed on a given day
    func isContainerCompleted(_ container: Activity, on day: Date, allActivities: [Activity], logs: [ActivityLog]) -> Bool {
        let children = container.historicalChildren(on: day, from: allActivities)
        guard !children.isEmpty else { return false }
        return children.allSatisfy { child in
            let completed = logs.filter {
                $0.activity?.id == child.id && $0.status == .completed && $0.date.isSameDay(as: day)
            }.count
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
            let dayCompleted = dayActivityLogs.filter { $0.status == .completed }.count

            if activity.isMultiSession {
                let sessions = activity.sessionsPerDay(on: day)
                var slotsDone = 0
                var slotsSkipped = 0
                for slot in activity.timeSlots {
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
                let daySkipped = dayActivityLogs.contains { $0.status == .skipped }
                if daySkipped && dayCompleted == 0 { continue }
                let sessions = activity.sessionsPerDay(on: day)
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
        var totalDays = 0
        var completedDays = 0

        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if vacationSet.contains(day) { continue }
            if let stopped = container.stoppedAt, day > stopped { continue }
            if day < container.createdDate.startOfDay { continue }

            let schedule = container.scheduleActive(on: day)
            guard schedule.isScheduled(on: day) else { continue }

            let children = container.historicalChildren(on: day, from: allActivities)
            let scheduledChildren = children.filter { child in
                if day < child.createdDate.startOfDay { return false }
                if let stopped = child.stoppedAt, day > stopped { return false }
                return child.scheduleActive(on: day).isScheduled(on: day)
            }
            guard !scheduledChildren.isEmpty else { continue }

            // Exclude days where all children are skipped (none completed)
            let allSkipped = scheduledChildren.allSatisfy { child in
                logs.contains { $0.activity?.id == child.id && $0.status == .skipped && $0.date.isSameDay(as: day) }
            }
            let anyCompleted = scheduledChildren.contains { child in
                logs.contains { $0.activity?.id == child.id && $0.status == .completed && $0.date.isSameDay(as: day) }
            }
            if allSkipped && !anyCompleted { continue }

            totalDays += 1
            let allDone = scheduledChildren.allSatisfy { child in
                let completed = logs.filter {
                    $0.activity?.id == child.id && $0.status == .completed && $0.date.isSameDay(as: day)
                }.count
                return completed >= child.sessionsPerDay(on: day)
            }
            if allDone { completedDays += 1 }
        }

        guard totalDays > 0 else { return 0 }
        return Double(completedDays) / Double(totalDays)
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
        let children = container.historicalChildren(on: day, from: allActivities)
        let scheduledChildren = children.filter { child in
            if day < child.createdDate.startOfDay { return false }
            if let stopped = child.stoppedAt, day > stopped { return false }
            return child.scheduleActive(on: day).isScheduled(on: day)
        }
        guard !scheduledChildren.isEmpty else { return false }
        let allSkipped = scheduledChildren.allSatisfy { child in
            logs.contains { $0.activity?.id == child.id && $0.status == .skipped && $0.date.isSameDay(as: day) }
        }
        let anyCompleted = scheduledChildren.contains { child in
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
