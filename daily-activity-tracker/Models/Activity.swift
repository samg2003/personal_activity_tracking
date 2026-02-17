import Foundation
import SwiftData

enum HealthKitMode: String, Sendable {
    case read
    case write
    case both
}

enum AggregationMode: String, Codable, CaseIterable, Identifiable {
    case sum
    case average

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .sum: "Total (Sum)"
        case .average: "Average"
        }
    }
}

@Model
final class Activity {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "circle"
    var hexColor: String = "#007AFF"

    // Stored as raw strings / Data for SwiftData safety
    var typeRaw: String = ActivityType.checkbox.rawValue
    var scheduleData: Data?
    var timeWindowData: Data?
    var timeSlotsData: Data?  // Encoded [TimeSlot] for multi-session

    var targetValue: Double?
    var unit: String?
    var metricKindRaw: String?  // Only when type == .metric
    var aggregationModeRaw: String?  // Only cumulative: "sum" (default) or "average"
    var sortOrder: Int = 0
    var isArchived: Bool = false
    var createdAt: Date?
    var stoppedAt: Date?  // Non-nil = stopped tracking on this date

    // HealthKit (future)
    var healthKitTypeID: String?
    var healthKitModeRaw: String?

    // MARK: - Relationships

    var category: Category?
    var parent: Activity?

    @Relationship(deleteRule: .cascade, inverse: \Activity.parent)
    var children: [Activity] = []

    @Relationship(deleteRule: .cascade, inverse: \ActivityLog.activity)
    var logs: [ActivityLog] = []

    @Relationship(deleteRule: .cascade, inverse: \ActivityConfigSnapshot.activity)
    var configSnapshots: [ActivityConfigSnapshot] = []

    @Relationship(deleteRule: .nullify, inverse: \GoalActivity.activity)
    var goalLinks: [GoalActivity] = []

    // MARK: - Computed (type-safe access to encoded properties)

    var type: ActivityType {
        get { ActivityType(rawValue: typeRaw) ?? .checkbox }
        set { typeRaw = newValue.rawValue }
    }

    var schedule: Schedule {
        get {
            guard let data = scheduleData else { return .daily }
            return (try? JSONDecoder().decode(Schedule.self, from: data)) ?? .daily
        }
        set {
            scheduleData = try? JSONEncoder().encode(newValue)
        }
    }

    var timeWindow: TimeWindow? {
        get {
            guard let data = timeWindowData else { return nil }
            return try? JSONDecoder().decode(TimeWindow.self, from: data)
        }
        set {
            timeWindowData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    var metricKind: MetricKind? {
        get { metricKindRaw.flatMap { MetricKind(rawValue: $0) } }
        set { metricKindRaw = newValue?.rawValue }
    }

    var aggregationMode: AggregationMode {
        get { aggregationModeRaw.flatMap { AggregationMode(rawValue: $0) } ?? .sum }
        set { aggregationModeRaw = newValue.rawValue }
    }

    var healthKitMode: HealthKitMode? {
        get { healthKitModeRaw.flatMap { HealthKitMode(rawValue: $0) } }
        set { healthKitModeRaw = newValue?.rawValue }
    }

    /// Multiple time slots for multi-session activities (e.g., morning + evening)
    var timeSlots: [TimeSlot] {
        get {
            if let data = timeSlotsData,
               let slots = try? JSONDecoder().decode([TimeSlot].self, from: data),
               !slots.isEmpty {
                return slots
            }
            // Fallback: single slot from legacy timeWindow
            return [timeWindow?.slot ?? .allDay]
        }
        set {
            if newValue.count <= 1 {
                timeSlotsData = nil
            } else {
                timeSlotsData = try? JSONEncoder().encode(newValue)
            }
        }
    }

    var isMultiSession: Bool { timeSlots.count > 1 }

    var isStopped: Bool { stoppedAt != nil }

    /// Safe accessor for createdAt (handles nil for pre-migration records)
    var createdDate: Date { createdAt ?? Date.distantPast }

    // MARK: - History-Aware Helpers

    /// Returns the config snapshot active on a given date, if any
    func configSnapshot(for date: Date) -> ActivityConfigSnapshot? {
        let day = date.startOfDay
        return configSnapshots.first { snap in
            snap.effectiveFrom <= day && day <= snap.effectiveUntil
        }
    }

    /// Schedule that was active on a given date (snapshot or current)
    func scheduleActive(on date: Date) -> Schedule {
        configSnapshot(for: date)?.schedule ?? schedule
    }

    /// Number of daily sessions active on a given date
    func sessionsPerDay(on date: Date) -> Int {
        configSnapshot(for: date)?.sessionsPerDay ?? max(timeSlots.count, 1)
    }

    /// Time slots that were active on a given date (snapshot or current)
    func timeSlotsActive(on date: Date) -> [TimeSlot] {
        configSnapshot(for: date)?.timeSlots ?? timeSlots
    }

    /// Whether this activity was multi-session on a given date
    func isMultiSession(on date: Date) -> Bool {
        timeSlotsActive(on: date).count > 1
    }

    /// Parent container ID on a given date (snapshot or current)
    func parentID(on date: Date) -> UUID? {
        configSnapshot(for: date)?.parentID ?? parent?.id
    }

    /// Returns children that belonged to this container on a given date.
    /// Includes current children AND any activity whose snapshot places it here historically.
    func historicalChildren(on date: Date, from allActivities: [Activity]) -> [Activity] {
        guard type == .container else { return [] }
        let day = date.startOfDay
        var result = Set(children.map { $0.id })
        // Also include activities whose snapshot parentID matches this container on that date
        for act in allActivities where act.parent?.id != self.id {
            if act.parentID(on: date) == self.id {
                result.insert(act.id)
            }
        }
        // Filter to children that existed on the given date
        return allActivities.filter { act in
            guard result.contains(act.id) else { return false }
            if act.createdDate.startOfDay > day { return false }
            if let stopped = act.stoppedAt, stopped < day { return false }
            return true
        }
    }

    // MARK: - Init

    init(
        name: String,
        icon: String = "circle",
        hexColor: String = "#007AFF",
        type: ActivityType = .checkbox,
        schedule: Schedule = .daily,
        timeWindow: TimeWindow? = nil,
        category: Category? = nil,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.hexColor = hexColor
        self.typeRaw = type.rawValue
        self.category = category
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.scheduleData = try? JSONEncoder().encode(schedule)
        self.timeWindowData = timeWindow.flatMap { try? JSONEncoder().encode($0) }
    }
    // MARK: - Aggregation Helpers

    /// Aggregate log values for a single day — sum or average based on aggregation mode.
    /// Use this whenever combining multiple log entries into one daily value.
    func aggregateDayValue(from values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        switch aggregationMode {
        case .sum:     return values.reduce(0, +)
        case .average: return values.reduce(0, +) / Double(values.count)
        }
    }

    /// Aggregate across multiple days (for weekly/monthly/annual charts).
    /// First computes per-day values via `aggregateDayValue`, then averages those daily values
    /// for `.average` mode, or sums them for `.sum` mode.
    func aggregateMultiDayValue(from logs: [ActivityLog]) -> Double {
        let byDay = Dictionary(grouping: logs.filter { $0.status == .completed }) { $0.date.startOfDay }
        let dailyValues = byDay.values.compactMap { dayLogs -> Double? in
            let vals = dayLogs.compactMap(\.value)
            guard !vals.isEmpty else { return nil }
            return aggregateDayValue(from: vals)
        }
        guard !dailyValues.isEmpty else { return 0 }
        switch aggregationMode {
        case .sum:     return dailyValues.reduce(0, +)
        case .average: return dailyValues.reduce(0, +) / Double(dailyValues.count)
        }
    }
}
