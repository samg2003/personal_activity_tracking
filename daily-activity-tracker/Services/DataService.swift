import SwiftUI
import SwiftData

@MainActor
final class DataService {
    static let shared = DataService()
    
    // MARK: - DTOs
    
    struct ExportPackage: Codable {
        let version: String
        let timestamp: Date
        let categories: [CategoryDTO]
        let activities: [ActivityDTO]
        let logs: [LogDTO]
        let vacationDays: [VacationDTO]
        var configSnapshots: [ConfigSnapshotDTO]?
    }
    
    struct CategoryDTO: Codable {
        let id: UUID
        let name: String
        let icon: String
        let hexColor: String
        let sortOrder: Int
    }
    
    struct ActivityDTO: Codable {
        let id: UUID
        let name: String
        let icon: String
        let hexColor: String
        let typeRaw: String
        let scheduleData: Data?
        let timeWindowData: Data?
        let timeSlotsData: Data?
        let reminderData: Data?
        let targetValue: Double?
        let unit: String?
        let allowsPhoto: Bool
        let allowsNotes: Bool
        let weight: Double
        let sortOrder: Int
        let isArchived: Bool
        let createdAt: Date
        let categoryID: UUID?
        let parentID: UUID?
        var stoppedAt: Date?
        let healthKitTypeID: String?
        let healthKitModeRaw: String?

        init(id: UUID, name: String, icon: String, hexColor: String,
             typeRaw: String, scheduleData: Data?, timeWindowData: Data?,
             timeSlotsData: Data?, reminderData: Data?,
             targetValue: Double?, unit: String?,
             allowsPhoto: Bool, allowsNotes: Bool,
             weight: Double, sortOrder: Int, isArchived: Bool,
             createdAt: Date, categoryID: UUID?, parentID: UUID?,
             stoppedAt: Date? = nil,
             healthKitTypeID: String? = nil, healthKitModeRaw: String? = nil) {
            self.id = id; self.name = name; self.icon = icon; self.hexColor = hexColor
            self.typeRaw = typeRaw; self.scheduleData = scheduleData
            self.timeWindowData = timeWindowData; self.timeSlotsData = timeSlotsData
            self.reminderData = reminderData; self.targetValue = targetValue; self.unit = unit
            self.allowsPhoto = allowsPhoto; self.allowsNotes = allowsNotes
            self.weight = weight; self.sortOrder = sortOrder; self.isArchived = isArchived
            self.createdAt = createdAt; self.categoryID = categoryID; self.parentID = parentID
            self.stoppedAt = stoppedAt; self.healthKitTypeID = healthKitTypeID
            self.healthKitModeRaw = healthKitModeRaw
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "star.fill"
            hexColor = try c.decodeIfPresent(String.self, forKey: .hexColor) ?? "#007AFF"
            typeRaw = try c.decodeIfPresent(String.self, forKey: .typeRaw) ?? "checkbox"
            scheduleData = try c.decodeIfPresent(Data.self, forKey: .scheduleData)
            timeWindowData = try c.decodeIfPresent(Data.self, forKey: .timeWindowData)
            timeSlotsData = try c.decodeIfPresent(Data.self, forKey: .timeSlotsData)
            reminderData = try c.decodeIfPresent(Data.self, forKey: .reminderData)
            targetValue = try c.decodeIfPresent(Double.self, forKey: .targetValue)
            unit = try c.decodeIfPresent(String.self, forKey: .unit)
            allowsPhoto = try c.decodeIfPresent(Bool.self, forKey: .allowsPhoto) ?? false
            allowsNotes = try c.decodeIfPresent(Bool.self, forKey: .allowsNotes) ?? false
            weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? 1.0
            sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
            isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
            createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
            categoryID = try c.decodeIfPresent(UUID.self, forKey: .categoryID)
            parentID = try c.decodeIfPresent(UUID.self, forKey: .parentID)
            stoppedAt = try c.decodeIfPresent(Date.self, forKey: .stoppedAt)
            healthKitTypeID = try c.decodeIfPresent(String.self, forKey: .healthKitTypeID)
            healthKitModeRaw = try c.decodeIfPresent(String.self, forKey: .healthKitModeRaw)
        }
    }
    
    struct LogDTO: Codable {
        let id: UUID
        let date: Date
        let statusRaw: String
        let value: Double?
        let photoFilename: String?
        let note: String?
        let skipReason: String?
        let timeSlotRaw: String?
        let completedAt: Date?
        let activityID: UUID

        init(id: UUID, date: Date, statusRaw: String, value: Double?,
             photoFilename: String?, note: String?, skipReason: String?,
             timeSlotRaw: String?, completedAt: Date?, activityID: UUID) {
            self.id = id; self.date = date; self.statusRaw = statusRaw
            self.value = value; self.photoFilename = photoFilename; self.note = note
            self.skipReason = skipReason; self.timeSlotRaw = timeSlotRaw
            self.completedAt = completedAt; self.activityID = activityID
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            date = try c.decode(Date.self, forKey: .date)
            statusRaw = try c.decodeIfPresent(String.self, forKey: .statusRaw) ?? "completed"
            value = try c.decodeIfPresent(Double.self, forKey: .value)
            photoFilename = try c.decodeIfPresent(String.self, forKey: .photoFilename)
            note = try c.decodeIfPresent(String.self, forKey: .note)
            skipReason = try c.decodeIfPresent(String.self, forKey: .skipReason)
            timeSlotRaw = try c.decodeIfPresent(String.self, forKey: .timeSlotRaw)
            completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
            activityID = try c.decode(UUID.self, forKey: .activityID)
        }
    }
    
    struct VacationDTO: Codable {
        let date: Date
    }

    struct ConfigSnapshotDTO: Codable {
        let id: UUID
        let activityID: UUID
        let effectiveFrom: Date
        let effectiveUntil: Date
        let scheduleData: Data?
        let timeWindowData: Data?
        let timeSlotsData: Data?
        let typeRaw: String
        let targetValue: Double?
        let unit: String?
        let parentID: UUID?

        init(id: UUID, activityID: UUID, effectiveFrom: Date, effectiveUntil: Date,
             scheduleData: Data?, timeWindowData: Data?, timeSlotsData: Data?,
             typeRaw: String, targetValue: Double?, unit: String?, parentID: UUID?) {
            self.id = id; self.activityID = activityID
            self.effectiveFrom = effectiveFrom; self.effectiveUntil = effectiveUntil
            self.scheduleData = scheduleData; self.timeWindowData = timeWindowData
            self.timeSlotsData = timeSlotsData; self.typeRaw = typeRaw
            self.targetValue = targetValue; self.unit = unit; self.parentID = parentID
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            activityID = try c.decode(UUID.self, forKey: .activityID)
            effectiveFrom = try c.decode(Date.self, forKey: .effectiveFrom)
            effectiveUntil = try c.decode(Date.self, forKey: .effectiveUntil)
            scheduleData = try c.decodeIfPresent(Data.self, forKey: .scheduleData)
            timeWindowData = try c.decodeIfPresent(Data.self, forKey: .timeWindowData)
            timeSlotsData = try c.decodeIfPresent(Data.self, forKey: .timeSlotsData)
            typeRaw = try c.decodeIfPresent(String.self, forKey: .typeRaw) ?? "checkbox"
            targetValue = try c.decodeIfPresent(Double.self, forKey: .targetValue)
            unit = try c.decodeIfPresent(String.self, forKey: .unit)
            parentID = try c.decodeIfPresent(UUID.self, forKey: .parentID)
        }
    }
    
    // MARK: - Export
    
    func exportData(context: ModelContext) throws -> String {
        // Fetch all data
        let categories = try context.fetch(FetchDescriptor<Category>())
        let activities = try context.fetch(FetchDescriptor<Activity>())
        let logs = try context.fetch(FetchDescriptor<ActivityLog>())
        let vacationDays = try context.fetch(FetchDescriptor<VacationDay>())
        
        // Map to DTOs
        let catDTOs = categories.map {
            CategoryDTO(id: $0.id, name: $0.name, icon: $0.icon, hexColor: $0.hexColor, sortOrder: $0.sortOrder)
        }
        
        let actDTOs = activities.map {
            ActivityDTO(
                id: $0.id, name: $0.name, icon: $0.icon, hexColor: $0.hexColor,
                typeRaw: $0.typeRaw,
                scheduleData: $0.scheduleData,
                timeWindowData: $0.timeWindowData,
                timeSlotsData: $0.timeSlotsData,
                reminderData: $0.reminderData,
                targetValue: $0.targetValue,
                unit: $0.unit,
                allowsPhoto: $0.allowsPhoto,
                allowsNotes: $0.allowsNotes,
                weight: $0.weight,
                sortOrder: $0.sortOrder,
                isArchived: $0.isArchived,
                createdAt: $0.createdAt,
                categoryID: $0.category?.id,
                parentID: $0.parent?.id,
                stoppedAt: $0.stoppedAt,
                healthKitTypeID: $0.healthKitTypeID,
                healthKitModeRaw: $0.healthKitModeRaw
            )
        }
        
        let logDTOs = logs.compactMap { log -> LogDTO? in
            guard let actID = log.activity?.id else { return nil }
            return LogDTO(
                id: log.id, date: log.date, statusRaw: log.statusRaw,
                value: log.value, photoFilename: log.photoFilename,
                note: log.note, skipReason: log.skipReason,
                timeSlotRaw: log.timeSlotRaw,
                completedAt: log.completedAt, activityID: actID
            )
        }
        
        let vacDTOs = vacationDays.map { VacationDTO(date: $0.date) }

        // Config Snapshots
        let snapshots = try context.fetch(FetchDescriptor<ActivityConfigSnapshot>())
        let snapDTOs = snapshots.compactMap { snap -> ConfigSnapshotDTO? in
            guard let actID = snap.activity?.id else { return nil }
            return ConfigSnapshotDTO(
                id: snap.id, activityID: actID,
                effectiveFrom: snap.effectiveFrom,
                effectiveUntil: snap.effectiveUntil,
                scheduleData: snap.scheduleData,
                timeWindowData: snap.timeWindowData,
                timeSlotsData: snap.timeSlotsData,
                typeRaw: snap.typeRaw,
                targetValue: snap.targetValue,
                unit: snap.unit,
                parentID: snap.parentID
            )
        }

        // Create Package
        let package = ExportPackage(
            version: "1.0",
            timestamp: Date(),
            categories: catDTOs,
            activities: actDTOs,
            logs: logDTOs,
            vacationDays: vacDTOs,
            configSnapshots: snapDTOs
        )
        
        // Encode
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(package)
        
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    // MARK: - Import
    
    func restoreData(json: String, context: ModelContext) throws {
        guard let data = json.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let package = try decoder.decode(ExportPackage.self, from: data)
        
        // Clear existing data (Safe Mode: Fetch & Delete)
        // Batch delete .delete(model:) can fail with "mandatory OTO nullify inverse" on complex graphs.
        // Explicitly deleting objects ensures SwiftData/CoreData relationships are respected.
        
        let logs = try context.fetch(FetchDescriptor<ActivityLog>())
        for log in logs { context.delete(log) }
        
        let activities = try context.fetch(FetchDescriptor<Activity>())
        for activity in activities { context.delete(activity) }
        
        let categories = try context.fetch(FetchDescriptor<Category>())
        for category in categories { context.delete(category) }
        
        let vacations = try context.fetch(FetchDescriptor<VacationDay>())
        for vacation in vacations { context.delete(vacation) }

        let snapshots = try context.fetch(FetchDescriptor<ActivityConfigSnapshot>())
        for snap in snapshots { context.delete(snap) }
        
        // Save to ensure clear state before insert
        try context.save()
        
        // Insert Categories
        var categoryMap: [UUID: Category] = [:]
        for dto in package.categories {
            let cat = Category(name: dto.name, icon: dto.icon, hexColor: dto.hexColor, sortOrder: dto.sortOrder)
            cat.id = dto.id
            context.insert(cat)
            categoryMap[dto.id] = cat
        }
        
        // Insert Activities (Pass 1: Creation)
        var activityMap: [UUID: Activity] = [:]
        for dto in package.activities {
            let act = Activity(
                name: dto.name, icon: dto.icon, hexColor: dto.hexColor,
                type: ActivityType(rawValue: dto.typeRaw) ?? .checkbox
            )
            act.id = dto.id
            act.scheduleData = dto.scheduleData
            act.timeWindowData = dto.timeWindowData
            act.timeSlotsData = dto.timeSlotsData
            act.reminderData = dto.reminderData
            act.targetValue = dto.targetValue
            act.unit = dto.unit
            act.allowsPhoto = dto.allowsPhoto
            act.allowsNotes = dto.allowsNotes
            act.weight = dto.weight
            act.sortOrder = dto.sortOrder
            act.isArchived = dto.isArchived
            act.createdAt = dto.createdAt
            act.stoppedAt = dto.stoppedAt
            act.healthKitTypeID = dto.healthKitTypeID
            act.healthKitModeRaw = dto.healthKitModeRaw
            
            context.insert(act)
            activityMap[dto.id] = act
        }
        
        // Link Relationships (Pass 2)
        for dto in package.activities {
            guard let act = activityMap[dto.id] else { continue }
            if let catID = dto.categoryID {
                act.category = categoryMap[catID]
            }
            if let parentID = dto.parentID {
                act.parent = activityMap[parentID]
            }
        }
        
        // Insert Logs
        for dto in package.logs {
            guard let act = activityMap[dto.activityID] else { continue }
            let log = ActivityLog(activity: act, date: dto.date, status: LogStatus(rawValue: dto.statusRaw) ?? .completed, value: dto.value)
            log.id = dto.id
            log.photoFilename = dto.photoFilename
            log.note = dto.note
            log.skipReason = dto.skipReason
            log.timeSlotRaw = dto.timeSlotRaw
            log.completedAt = dto.completedAt
            context.insert(log)
        }
        
        // Insert Vacation Days
        for dto in package.vacationDays {
            let vac = VacationDay(date: dto.date)
            context.insert(vac)
        }

        // Insert Config Snapshots
        if let snapDTOs = package.configSnapshots {
            for dto in snapDTOs {
                guard let act = activityMap[dto.activityID] else { continue }
                let snap = ActivityConfigSnapshot(
                    activity: act,
                    effectiveFrom: dto.effectiveFrom,
                    effectiveUntil: dto.effectiveUntil
                )
                snap.id = dto.id
                snap.scheduleData = dto.scheduleData
                snap.timeWindowData = dto.timeWindowData
                snap.timeSlotsData = dto.timeSlotsData
                snap.typeRaw = dto.typeRaw
                snap.targetValue = dto.targetValue
                snap.unit = dto.unit
                snap.parentID = dto.parentID
                context.insert(snap)
            }
        }

        try context.save()
    }
}
