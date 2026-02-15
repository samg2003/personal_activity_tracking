import Foundation

/// Determines which activities should appear on a given date.
protocol ScheduleEngineProtocol {
    func shouldShow(_ activity: Activity, on date: Date) -> Bool
    func activitiesForToday(from activities: [Activity], on date: Date, vacationDays: [VacationDay]) -> [Activity]
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

    func activitiesForToday(from activities: [Activity], on date: Date, vacationDays: [VacationDay]) -> [Activity] {
        // Vacation days are now handled by auto-skip logs, not by hiding activities

        return activities
            .filter { $0.parent == nil && $0.parentID(on: date) == nil }  // only top-level (current + historical)
            .filter { shouldShow($0, on: date) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}
