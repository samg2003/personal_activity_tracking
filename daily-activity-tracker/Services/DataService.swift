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
        
        // Advanced
        let healthKitTypeID: String?
        let healthKitModeRaw: String?
    }
    
    struct LogDTO: Codable {
        let id: UUID
        let date: Date
        let statusRaw: String
        let value: Double?
        let photoFilename: String?
        let note: String?
        let skipReason: String?
        let completedAt: Date?
        let activityID: UUID
    }
    
    struct VacationDTO: Codable {
        let date: Date
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
                completedAt: log.completedAt, activityID: actID
            )
        }
        
        let vacDTOs = vacationDays.map { VacationDTO(date: $0.date) }
        
        // Create Package
        let package = ExportPackage(
            version: "1.0",
            timestamp: Date(),
            categories: catDTOs,
            activities: actDTOs,
            logs: logDTOs,
            vacationDays: vacDTOs
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
            act.reminderData = dto.reminderData
            act.targetValue = dto.targetValue
            act.unit = dto.unit
            act.allowsPhoto = dto.allowsPhoto
            act.allowsNotes = dto.allowsNotes
            act.weight = dto.weight
            act.sortOrder = dto.sortOrder
            act.isArchived = dto.isArchived
            act.createdAt = dto.createdAt
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
            log.completedAt = dto.completedAt
            context.insert(log)
        }
        
        // Insert Vacation Days
        for dto in package.vacationDays {
            let vac = VacationDay(date: dto.date)
            context.insert(vac)
        }
        
        try context.save()
    }
}
