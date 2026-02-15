import Foundation
import SwiftData

/// Stores a time-bounded snapshot of an activity's structural config.
/// Created when the user edits an activity with "Future only" — preserves
/// what the config looked like for a specific date range so analytics
/// can use the correct schedule/type/parent for historical dates.
@Model
final class ActivityConfigSnapshot {
    var id: UUID = UUID()
    var effectiveFrom: Date = Date()
    var effectiveUntil: Date = Date()

    // Structural config at that point in time
    var scheduleData: Data?
    var timeWindowData: Data?
    var timeSlotsData: Data?
    var typeRaw: String = ActivityType.checkbox.rawValue
    var targetValue: Double?
    var unit: String?

    /// Container this activity belonged to during this period
    var parentID: UUID?

    var activity: Activity?

    // MARK: - Computed accessors

    var schedule: Schedule {
        guard let data = scheduleData else { return .daily }
        return (try? JSONDecoder().decode(Schedule.self, from: data)) ?? .daily
    }

    var type: ActivityType {
        ActivityType(rawValue: typeRaw) ?? .checkbox
    }

    var timeSlots: [TimeSlot] {
        if let data = timeSlotsData,
           let slots = try? JSONDecoder().decode([TimeSlot].self, from: data),
           !slots.isEmpty {
            return slots
        }
        if let data = timeWindowData,
           let tw = try? JSONDecoder().decode(TimeWindow.self, from: data) {
            return [tw.slot]
        }
        return [.allDay]
    }

    var sessionsPerDay: Int {
        max(timeSlots.count, 1)
    }

    // MARK: - Init

    /// Capture the current structural config from an activity
    init(activity: Activity, effectiveFrom: Date, effectiveUntil: Date) {
        self.id = UUID()
        self.activity = activity
        self.effectiveFrom = effectiveFrom.startOfDay
        self.effectiveUntil = effectiveUntil.startOfDay
        self.scheduleData = activity.scheduleData
        self.timeWindowData = activity.timeWindowData
        self.timeSlotsData = activity.timeSlotsData
        self.typeRaw = activity.typeRaw
        self.targetValue = activity.targetValue
        self.unit = activity.unit
        self.parentID = activity.parent?.id
    }
}
