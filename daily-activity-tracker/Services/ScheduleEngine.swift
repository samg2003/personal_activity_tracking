import Foundation

/// Determines which activities should appear on a given date.
protocol ScheduleEngineProtocol {
    func shouldShow(_ activity: Activity, on date: Date) -> Bool
    func activitiesForToday(from activities: [Activity], on date: Date, vacationDays: [VacationDay]) -> [Activity]
    func activitiesForToday(from activities: [Activity], on date: Date, vacationDays: [VacationDay], logs: [ActivityLog]) -> [Activity]
    func carriedForwardDate(for activity: Activity, on date: Date, logs: [ActivityLog]) -> Date?
    func completionStatus(on date: Date, activities: [Activity], logs: [ActivityLog], vacationDays: [VacationDay]) -> DayCompletionStatus
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
        case .daily:
            return true
        case .weekly:
            guard let weekdays = schedule.weekdays else { return true }
            return weekdays.contains(date.weekdayISO)
        case .monthly:
            guard let monthDays = schedule.monthDays else { return true }
            return monthDays.contains(date.dayOfMonth)
        case .sticky:
            return !activity.logs.contains { $0.status == .completed }
        case .adhoc:
            guard let specificDate = schedule.specificDate else { return false }
            return date.isSameDay(as: specificDate)
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
            let wasScheduled: Bool
            switch historicalSchedule.type {
            case .weekly:
                wasScheduled = (historicalSchedule.weekdays ?? []).contains(checkDate.weekdayISO)
            case .monthly:
                wasScheduled = (historicalSchedule.monthDays ?? []).contains(checkDate.dayOfMonth)
            default:
                wasScheduled = false
            }

            guard wasScheduled else { continue }

            // Found most recent scheduled day — check if completed/skipped that day OR today
            let done = logs.contains {
                $0.activity?.id == activity.id &&
                (calendar.isDate($0.date, inSameDayAs: checkDate) || calendar.isDate($0.date, inSameDayAs: date)) &&
                ($0.status == .completed || $0.status == .skipped)
            }

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
            let actSkipped = dayLogs.contains {
                $0.activity?.id == activity.id && $0.status == .skipped
            }

            if activity.type == .container {
                let children = activity.historicalChildren(on: date, from: activities)
                    .filter { shouldShow($0, on: date) }
                for child in children {
                    let childSkipped = dayLogs.contains {
                        $0.activity?.id == child.id && $0.status == .skipped
                    }
                    if childSkipped { skippedCount += 1; continue }
                    total += 1
                    if dayLogs.contains(where: { $0.activity?.id == child.id && $0.status == .completed }) {
                        done += 1
                    }
                }
            } else if activity.type == .cumulative && (activity.targetValue == nil || activity.targetValue == 0) {
                if actSkipped { skippedCount += 1 }
            } else if actSkipped {
                skippedCount += 1
            } else if activity.type == .cumulative, let target = activity.targetValue, target > 0 {
                total += 1.0
                let values = dayLogs
                    .filter { $0.activity?.id == activity.id && $0.status == .completed }
                    .compactMap(\.value)
                let cumVal = activity.aggregateDayValue(from: values)
                done += min(cumVal / target, 1.0)
            } else {
                let sessions = Double(activity.sessionsPerDay(on: date))
                total += sessions
                let completedCount = Double(dayLogs.filter {
                    $0.activity?.id == activity.id && $0.status == .completed
                }.count)
                done += min(completedCount, sessions)
            }
        }

        if total <= 0 && skippedCount > 0 { return .skipped }
        guard total > 0 else { return .noData }
        return DayCompletionStatus(rate: done / total, allSkipped: false)
    }
}
