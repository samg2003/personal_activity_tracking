import Foundation

/// Determines which activities should appear on a given date.
protocol ScheduleEngineProtocol {
    func shouldShow(_ activity: Activity, on date: Date) -> Bool
    func activitiesForToday(from activities: [Activity], on date: Date, vacationDays: [VacationDay]) -> [Activity]
}

final class ScheduleEngine: ScheduleEngineProtocol {

    func shouldShow(_ activity: Activity, on date: Date) -> Bool {
        guard !activity.isArchived else { return false }

        let schedule = activity.schedule
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
            // Show until there's a completed log
            return !activity.logs.contains { $0.status == .completed }
        case .adhoc:
            guard let specificDate = schedule.specificDate else { return false }
            // Show if it's the right day and not yet completed
            let completed = activity.logs.contains {
                $0.date.isSameDay(as: specificDate) && $0.status == .completed
            }
            return date.isSameDay(as: specificDate) && !completed
        }
    }

    func activitiesForToday(from activities: [Activity], on date: Date, vacationDays: [VacationDay]) -> [Activity] {
        if vacationDays.contains(where: { $0.date.isSameDay(as: date) }) {
            return []
        }

        return activities
            .filter { $0.parent == nil }   // only top-level
            .filter { shouldShow($0, on: date) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}
