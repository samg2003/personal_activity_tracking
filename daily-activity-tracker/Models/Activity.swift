import Foundation
import SwiftData

enum HealthKitMode: String, Sendable {
    case read
    case write
    case both
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
    var reminderData: Data?

    var targetValue: Double?
    var unit: String?
    var allowsPhoto: Bool = false
    var photoCadenceRaw: String = PhotoCadence.never.rawValue
    var allowsNotes: Bool = false
    var weight: Double = 1.0
    var sortOrder: Int = 0
    var isArchived: Bool = false
    var createdAt: Date = Date()
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

    var reminder: ReminderPreset? {
        get {
            guard let data = reminderData else { return nil }
            return try? JSONDecoder().decode(ReminderPreset.self, from: data)
        }
        set {
            reminderData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    var healthKitMode: HealthKitMode? {
        get { healthKitModeRaw.flatMap { HealthKitMode(rawValue: $0) } }
        set { healthKitModeRaw = newValue?.rawValue }
    }

    var photoCadence: PhotoCadence {
        get { PhotoCadence(rawValue: photoCadenceRaw) ?? .never }
        set { photoCadenceRaw = newValue.rawValue }
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

    /// Parent container ID on a given date (snapshot or current)
    func parentID(on date: Date) -> UUID? {
        configSnapshot(for: date)?.parentID ?? parent?.id
    }

    /// Returns children that belonged to this container on a given date.
    /// Includes current children AND any activity whose snapshot places it here historically.
    func historicalChildren(on date: Date, from allActivities: [Activity]) -> [Activity] {
        guard type == .container else { return [] }
        var result = Set(children.map { $0.id })
        // Also include activities whose snapshot parentID matches this container on that date
        for act in allActivities where act.parent?.id != self.id {
            if act.parentID(on: date) == self.id {
                result.insert(act.id)
            }
        }
        return allActivities.filter { result.contains($0.id) }
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
}
