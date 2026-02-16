import Foundation

/// Determines which activities should appear on a given date.
protocol ScheduleEngineProtocol {
    func shouldShow(_ activity: Activity, on date: Date) -> Bool
    func activitiesForToday(from activities: [Activity], on date: Date, vacationDays: [VacationDay]) -> [Activity]
    func activitiesForToday(from activities: [Activity], on date: Date, vacationDays: [VacationDay], logs: [ActivityLog]) -> [Activity]
    func carriedForwardDate(for activity: Activity, on date: Date, logs: [ActivityLog]) -> Date?
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
