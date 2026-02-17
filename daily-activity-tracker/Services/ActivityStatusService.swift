import Foundation

/// Single source of truth for an activity's completion/skip status on a given day.
/// Consolidates logic previously duplicated across DashboardView, ContainerRowView, and GoalDetailView.
struct ActivityStatusService {
    let date: Date
    let todayLogs: [ActivityLog]
    let allLogs: [ActivityLog]
    let allActivities: [Activity]
    let vacationDays: [VacationDay]
    let scheduleEngine: ScheduleEngineProtocol

    // MARK: - Vacation

    var isVacationDay: Bool {
        vacationDays.contains { $0.date.startOfDay == date.startOfDay }
    }

    // MARK: - Session-Level Checks (multi-session)

    func isSessionCompleted(_ activity: Activity, slot: TimeSlot) -> Bool {
        todayLogs.contains {
            $0.activity?.id == activity.id && $0.status == .completed && $0.timeSlot == slot
        }
    }

    func isSessionSkipped(_ activity: Activity, slot: TimeSlot) -> Bool {
        todayLogs.contains {
            $0.activity?.id == activity.id && $0.status == .skipped && $0.timeSlot == slot
        }
    }

    // MARK: - Activity-Level Checks

    func isFullyCompleted(_ activity: Activity) -> Bool {
        if activity.isMultiSession {
            return activity.timeSlots.allSatisfy { isSessionCompleted(activity, slot: $0) }
        }
        switch activity.type {
        case .checkbox, .metric, .value:
            return todayLogs.contains { $0.activity?.id == activity.id && $0.status == .completed }
        case .cumulative:
            guard let target = activity.targetValue, target > 0 else { return false }
            return cumulativeValue(for: activity) >= target
        case .container:
            let applicable = applicableChildren(activity)
            guard !applicable.isEmpty else { return false }
            return applicable.allSatisfy { isFullyCompleted($0) }
        }
    }

    func isSkipped(_ activity: Activity) -> Bool {
        if activity.type == .container {
            let applicable = applicableChildren(activity)
            guard !applicable.isEmpty else { return false }
            let nonCompleted = applicable.filter { !isFullyCompleted($0) }
            return !nonCompleted.isEmpty && nonCompleted.allSatisfy { child in
                if child.isMultiSession {
                    let nonCompletedSlots = child.timeSlots.filter { !isSessionCompleted(child, slot: $0) }
                    return !nonCompletedSlots.isEmpty && nonCompletedSlots.allSatisfy { isSessionSkipped(child, slot: $0) }
                }
                return todayLogs.contains { $0.activity?.id == child.id && $0.status == .skipped }
            }
        }
        if activity.isMultiSession {
            let nonCompleted = activity.timeSlots.filter { !isSessionCompleted(activity, slot: $0) }
            return !nonCompleted.isEmpty && nonCompleted.allSatisfy { isSessionSkipped(activity, slot: $0) }
        }
        return todayLogs.contains { $0.activity?.id == activity.id && $0.status == .skipped }
    }

    // MARK: - Skip Reason

    func skipReason(for activity: Activity) -> String? {
        if activity.type == .container {
            let applicable = applicableChildren(activity)
            return applicable.compactMap { child in
                todayLogs.first(where: { $0.activity?.id == child.id && $0.status == .skipped })?.skipReason
            }.first
        }
        return todayLogs.first(where: {
            $0.activity?.id == activity.id && $0.status == .skipped
        })?.skipReason
    }

    // MARK: - Value Queries

    func latestValue(for activity: Activity, slot: TimeSlot? = nil) -> Double? {
        if let slot, activity.isMultiSession {
            return todayLogs.first(where: {
                $0.activity?.id == activity.id && $0.status == .completed && $0.timeSlot == slot
            })?.value
        }
        return todayLogs.first(where: { $0.activity?.id == activity.id && $0.status == .completed })?.value
    }

    func cumulativeValue(for activity: Activity) -> Double {
        let values = todayLogs
            .filter { $0.activity?.id == activity.id && $0.status == .completed }
            .compactMap(\.value)
        return activity.aggregateDayValue(from: values)
    }

    // MARK: - Multi-Session Helpers

    func skippedSlots(for activity: Activity) -> [TimeSlot] {
        activity.timeSlots.filter { slot in
            isSessionSkipped(activity, slot: slot) && !isSessionCompleted(activity, slot: slot)
        }
    }

    // MARK: - Container

    func applicableChildren(_ container: Activity) -> [Activity] {
        scheduleEngine.applicableChildren(for: container, on: date, allActivities: allActivities, logs: allLogs)
    }

    // MARK: - Completion Fraction (Progress Bar)

    func completionFraction(for activities: [Activity]) -> Double {
        var total = 0.0
        var done = 0.0
        var skippedCount = 0

        for activity in activities {
            // No-target cumulatives have no completion concept
            if activity.type == .cumulative && (activity.targetValue == nil || activity.targetValue == 0) { continue }

            if activity.type == .container {
                let children = applicableChildren(activity)
                var childTotal = 0.0
                var childDone = 0.0
                var childSkipped = 0.0
                for child in children {
                    if child.isMultiSession {
                        for slot in child.timeSlots {
                            if isSessionCompleted(child, slot: slot) {
                                childDone += 1.0
                                childTotal += 1.0
                            } else if isSessionSkipped(child, slot: slot) {
                                childSkipped += 1.0
                            } else {
                                childTotal += 1.0
                            }
                        }
                    } else if isSkipped(child) && !isFullyCompleted(child) {
                        childSkipped += 1.0
                    } else {
                        childTotal += 1.0
                        if isFullyCompleted(child) { childDone += 1.0 }
                    }
                }
                if childTotal <= 0 && childSkipped > 0 { skippedCount += 1; continue }
                total += childTotal
                done += childDone
            } else if activity.isMultiSession {
                var slotsDone = 0.0
                var slotsSkipped = 0.0
                for slot in activity.timeSlots {
                    if isSessionCompleted(activity, slot: slot) {
                        slotsDone += 1.0
                    } else if isSessionSkipped(activity, slot: slot) {
                        slotsSkipped += 1.0
                    }
                }
                let sessions = Double(activity.timeSlots.count)
                if slotsSkipped == sessions && slotsDone == 0 { skippedCount += 1; continue }
                total += sessions - slotsSkipped
                done += min(slotsDone, sessions - slotsSkipped)
            } else {
                if isSkipped(activity) { skippedCount += 1; continue }
                if activity.type == .cumulative, let target = activity.targetValue, target > 0 {
                    total += 1.0
                    done += min(cumulativeValue(for: activity) / target, 1.0)
                } else {
                    total += 1.0
                    if isFullyCompleted(activity) { done += 1.0 }
                }
            }
        }

        if total <= 0 && skippedCount > 0 { return 0.0 }
        guard total > 0 else { return 1.0 }
        return done / total
    }
}
