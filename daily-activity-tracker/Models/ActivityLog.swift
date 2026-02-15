import Foundation
import SwiftData

@Model
final class ActivityLog {
    var id: UUID = UUID()
    var date: Date = Date()
    var statusRaw: String = LogStatus.completed.rawValue
    var value: Double?
    var photoFilename: String?
    var note: String?
    var skipReason: String?
    var timeSlotRaw: String?
    var completedAt: Date?

    var activity: Activity?

    var status: LogStatus {
        get { LogStatus(rawValue: statusRaw) ?? .completed }
        set { statusRaw = newValue.rawValue }
    }

    /// Which time slot this log applies to (nil = single-session / legacy)
    var timeSlot: TimeSlot? {
        get { timeSlotRaw.flatMap { TimeSlot(rawValue: $0) } }
        set { timeSlotRaw = newValue?.rawValue }
    }

    init(
        activity: Activity,
        date: Date,
        status: LogStatus = .completed,
        value: Double? = nil
    ) {
        self.id = UUID()
        self.activity = activity
        self.date = date.startOfDay
        self.statusRaw = status.rawValue
        self.value = value
        self.completedAt = status == .completed ? Date() : nil
    }
}
