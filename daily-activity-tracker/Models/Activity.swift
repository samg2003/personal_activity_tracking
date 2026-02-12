import Foundation
import SwiftData

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
    var reminderData: Data?

    var targetValue: Double?
    var unit: String?
    var allowsPhoto: Bool = false
    var allowsNotes: Bool = false
    var weight: Double = 1.0
    var sortOrder: Int = 0
    var isArchived: Bool = false
    var createdAt: Date = Date()

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
        set { scheduleData = try? JSONEncoder().encode(newValue) }
    }

    var timeWindow: TimeWindow? {
        get {
            guard let data = timeWindowData else { return nil }
            return try? JSONDecoder().decode(TimeWindow.self, from: data)
        }
        set { timeWindowData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var reminder: ReminderPreset? {
        get {
            guard let data = reminderData else { return nil }
            return try? JSONDecoder().decode(ReminderPreset.self, from: data)
        }
        set { reminderData = newValue.flatMap { try? JSONEncoder().encode($0) } }
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
        // Encode complex types
        self.scheduleData = try? JSONEncoder().encode(schedule)
        self.timeWindowData = timeWindow.flatMap { try? JSONEncoder().encode($0) }
    }
}
