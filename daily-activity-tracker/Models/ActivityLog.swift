import Foundation
import SwiftData

@Model
final class ActivityLog {
    var id: UUID = UUID()
    var date: Date = Date()
    var statusRaw: String = LogStatus.completed.rawValue
    var value: Double?
    var photoFilename: String?     // Legacy: single photo
    var photoFilenamesData: Data?   // Multi-slot: JSON-encoded [String: String] (slot → filename)
    var note: String?
    var skipReason: String?
    var timeSlotRaw: String?
    var completedAt: Date?
    /// nil = manual entry, "healthkit" = synced from Apple Health
    var source: String?

    var activity: Activity?

    var isFromHealthKit: Bool { source == "healthkit" }

    var status: LogStatus {
        get { LogStatus(rawValue: statusRaw) ?? .completed }
        set { statusRaw = newValue.rawValue }
    }

    /// Which time slot this log applies to (nil = single-session / legacy)
    var timeSlot: TimeSlot? {
        get { timeSlotRaw.flatMap { TimeSlot(rawValue: $0) } }
        set { timeSlotRaw = newValue?.rawValue }
    }

    /// Multi-slot photo filenames (slot name → relative filename)
    var photoFilenames: [String: String] {
        get {
            if let data = photoFilenamesData,
               let map = try? JSONDecoder().decode([String: String].self, from: data) {
                return map
            }
            return [:]
        }
        set {
            photoFilenamesData = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue))
        }
    }

    /// All photo file paths from both legacy and multi-slot storage
    var allPhotoFiles: [String] {
        var files = Array(photoFilenames.values)
        if let legacy = photoFilename, !files.contains(legacy) {
            files.append(legacy)
        }
        return files
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
