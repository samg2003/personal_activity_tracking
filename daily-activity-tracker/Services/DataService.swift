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
        var goals: [GoalDTO]?
        var goalActivities: [GoalActivityDTO]?
        // Workout domain (v2.0)
        var exercises: [ExerciseDTO]?
        var exerciseMuscles: [ExerciseMuscleDTO]?
        var muscleGroups: [MuscleGroupDTO]?
        var workoutPlans: [WorkoutPlanDTO]?
        var workoutPlanDays: [WorkoutPlanDayDTO]?
        var strengthPlanExercises: [StrengthPlanExDTO]?
        var cardioPlanExercises: [CardioPlanExDTO]?
        var strengthSessions: [StrengthSessionDTO]?
        var workoutSetLogs: [WorkoutSetLogDTO]?
        var cardioSessions: [CardioSessionDTO]?
        var cardioSessionLogs: [CardioSessionLogDTO]?
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
        let targetValue: Double?
        let unit: String?
        let metricKindRaw: String?
        let photoSlotsData: Data?
        let sortOrder: Int
        let isArchived: Bool
        let createdAt: Date
        let categoryID: UUID?
        let parentID: UUID?
        var stoppedAt: Date?
        let healthKitTypeID: String?
        let healthKitModeRaw: String?
        let aggregationModeRaw: String?
        var pausedParentId: UUID?

        init(id: UUID, name: String, icon: String, hexColor: String,
             typeRaw: String, scheduleData: Data?, timeWindowData: Data?,
             timeSlotsData: Data?,
             targetValue: Double?, unit: String?, metricKindRaw: String?,
             photoSlotsData: Data? = nil,
             sortOrder: Int, isArchived: Bool,
             createdAt: Date, categoryID: UUID?, parentID: UUID?,
             stoppedAt: Date? = nil,
             healthKitTypeID: String? = nil, healthKitModeRaw: String? = nil,
             aggregationModeRaw: String? = nil,
             pausedParentId: UUID? = nil) {
            self.id = id; self.name = name; self.icon = icon; self.hexColor = hexColor
            self.typeRaw = typeRaw; self.scheduleData = scheduleData
            self.timeWindowData = timeWindowData; self.timeSlotsData = timeSlotsData
            self.targetValue = targetValue; self.unit = unit
            self.metricKindRaw = metricKindRaw
            self.photoSlotsData = photoSlotsData
            self.sortOrder = sortOrder; self.isArchived = isArchived
            self.createdAt = createdAt; self.categoryID = categoryID; self.parentID = parentID
            self.stoppedAt = stoppedAt; self.healthKitTypeID = healthKitTypeID
            self.healthKitModeRaw = healthKitModeRaw
            self.aggregationModeRaw = aggregationModeRaw
            self.pausedParentId = pausedParentId
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
            targetValue = try c.decodeIfPresent(Double.self, forKey: .targetValue)
            unit = try c.decodeIfPresent(String.self, forKey: .unit)
            metricKindRaw = try c.decodeIfPresent(String.self, forKey: .metricKindRaw)
            photoSlotsData = try c.decodeIfPresent(Data.self, forKey: .photoSlotsData)
            sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
            isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
            createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
            categoryID = try c.decodeIfPresent(UUID.self, forKey: .categoryID)
            parentID = try c.decodeIfPresent(UUID.self, forKey: .parentID)
            stoppedAt = try c.decodeIfPresent(Date.self, forKey: .stoppedAt)
            healthKitTypeID = try c.decodeIfPresent(String.self, forKey: .healthKitTypeID)
            healthKitModeRaw = try c.decodeIfPresent(String.self, forKey: .healthKitModeRaw)
            aggregationModeRaw = try c.decodeIfPresent(String.self, forKey: .aggregationModeRaw)
            pausedParentId = try c.decodeIfPresent(UUID.self, forKey: .pausedParentId)
            // Old fields silently ignored: allowsPhoto, allowsNotes, weight, reminderData
        }
    }
    
    struct LogDTO: Codable {
        let id: UUID
        let date: Date
        let statusRaw: String
        let value: Double?
        let photoFilename: String?
        let photoFilenamesData: Data?
        let note: String?
        let skipReason: String?
        let timeSlotRaw: String?
        let completedAt: Date?
        let source: String?
        let activityID: UUID

        init(id: UUID, date: Date, statusRaw: String, value: Double?,
             photoFilename: String?, photoFilenamesData: Data? = nil,
             note: String?, skipReason: String?,
             timeSlotRaw: String?, completedAt: Date?,
             source: String? = nil, activityID: UUID) {
            self.id = id; self.date = date; self.statusRaw = statusRaw
            self.value = value; self.photoFilename = photoFilename
            self.photoFilenamesData = photoFilenamesData
            self.note = note
            self.skipReason = skipReason; self.timeSlotRaw = timeSlotRaw
            self.completedAt = completedAt; self.source = source
            self.activityID = activityID
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            date = try c.decode(Date.self, forKey: .date)
            statusRaw = try c.decodeIfPresent(String.self, forKey: .statusRaw) ?? "completed"
            value = try c.decodeIfPresent(Double.self, forKey: .value)
            photoFilename = try c.decodeIfPresent(String.self, forKey: .photoFilename)
            photoFilenamesData = try c.decodeIfPresent(Data.self, forKey: .photoFilenamesData)
            note = try c.decodeIfPresent(String.self, forKey: .note)
            skipReason = try c.decodeIfPresent(String.self, forKey: .skipReason)
            timeSlotRaw = try c.decodeIfPresent(String.self, forKey: .timeSlotRaw)
            completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
            source = try c.decodeIfPresent(String.self, forKey: .source)
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

    struct GoalDTO: Codable {
        let id: UUID
        let title: String
        let icon: String
        let hexColor: String
        let deadline: Date?
        let isArchived: Bool
        let isManuallyPaused: Bool
        let createdAt: Date
        let sortOrder: Int

        init(id: UUID, title: String, icon: String, hexColor: String,
             deadline: Date?, isArchived: Bool, isManuallyPaused: Bool,
             createdAt: Date, sortOrder: Int) {
            self.id = id; self.title = title; self.icon = icon; self.hexColor = hexColor
            self.deadline = deadline; self.isArchived = isArchived
            self.isManuallyPaused = isManuallyPaused
            self.createdAt = createdAt; self.sortOrder = sortOrder
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            title = try c.decode(String.self, forKey: .title)
            icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "target"
            hexColor = try c.decodeIfPresent(String.self, forKey: .hexColor) ?? "#FF3B30"
            deadline = try c.decodeIfPresent(Date.self, forKey: .deadline)
            isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
            isManuallyPaused = try c.decodeIfPresent(Bool.self, forKey: .isManuallyPaused) ?? false
            createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
            sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        }
    }

    struct GoalActivityDTO: Codable {
        let id: UUID
        let goalID: UUID
        let activityID: UUID
        let roleRaw: String
        let weight: Double
        let metricBaseline: Double?
        let metricTarget: Double?
        let metricDirectionRaw: String?

        init(id: UUID, goalID: UUID, activityID: UUID, roleRaw: String,
             weight: Double, metricBaseline: Double?, metricTarget: Double?,
             metricDirectionRaw: String?) {
            self.id = id; self.goalID = goalID; self.activityID = activityID
            self.roleRaw = roleRaw; self.weight = weight
            self.metricBaseline = metricBaseline; self.metricTarget = metricTarget
            self.metricDirectionRaw = metricDirectionRaw
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            goalID = try c.decode(UUID.self, forKey: .goalID)
            activityID = try c.decode(UUID.self, forKey: .activityID)
            roleRaw = try c.decodeIfPresent(String.self, forKey: .roleRaw) ?? "activity"
            weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? 1.0
            metricBaseline = try c.decodeIfPresent(Double.self, forKey: .metricBaseline)
            metricTarget = try c.decodeIfPresent(Double.self, forKey: .metricTarget)
            metricDirectionRaw = try c.decodeIfPresent(String.self, forKey: .metricDirectionRaw)
        }
    }

    // MARK: - Workout Domain DTOs

    struct ExerciseDTO: Codable {
        let id: UUID
        let name: String
        let equipment: String
        let exerciseTypeRaw: String
        let aliasesData: Data?
        let videoURLsData: Data?
        let notes: String?
        let distanceUnit: String?
        let paceUnit: String?
        let availableMetricsData: Data?
        let isPreSeeded: Bool
        let createdAt: Date
    }

    struct ExerciseMuscleDTO: Codable {
        let id: UUID
        let exerciseID: UUID
        let muscleGroupID: UUID?
        let involvementScore: Double
    }

    struct MuscleGroupDTO: Codable {
        let id: UUID
        let name: String
        let parentID: UUID?
        let sortOrder: Int
        let mevSets: Int
        let mavSets: Int
        let mrvSets: Int
        let isPreSeeded: Bool
    }

    struct WorkoutPlanDTO: Codable {
        let id: UUID
        let name: String
        let planTypeRaw: String
        let statusRaw: String
        let containerActivityID: UUID?
        let createdAt: Date
    }

    struct WorkoutPlanDayDTO: Codable {
        let id: UUID
        let weekday: Int
        let dayLabel: String
        let isLabelOverridden: Bool
        let isRest: Bool
        let colorGroup: Int
        let planID: UUID
    }

    struct StrengthPlanExDTO: Codable {
        let id: UUID
        let targetSets: Int
        let rir: Int
        let sortOrder: Int
        let supersetGroup: String?
        let exerciseID: UUID?
        let planDayID: UUID
    }

    struct CardioPlanExDTO: Codable {
        let id: UUID
        let sessionTypeRaw: String
        let targetDistance: Double?
        let targetDurationMin: Int?
        let sessionParamsData: Data?
        let sortOrder: Int
        let exerciseID: UUID?
        let planDayID: UUID
    }

    struct StrengthSessionDTO: Codable {
        let id: UUID
        let planName: String
        let dayLabel: String
        let weekday: Int
        let date: Date
        let startedAt: Date
        let pausedAt: Date?
        let endedAt: Date?
        let totalPausedSeconds: Double
        let statusRaw: String
        let notes: String?
        let resumedAtSetCount: Int
        let resumedAtEndedAt: Date?
        let resumedAtPausedSeconds: Double
        let planDayID: UUID?
    }

    struct WorkoutSetLogDTO: Codable {
        let id: UUID
        let setNumber: Int
        let reps: Int
        let weight: Double
        let durationSeconds: Int?
        let isWarmup: Bool
        let completedAt: Date
        let exerciseID: UUID?
        let sessionID: UUID
    }

    struct CardioSessionDTO: Codable {
        let id: UUID
        let planName: String
        let dayLabel: String
        let weekday: Int
        let date: Date
        let startedAt: Date
        let pausedAt: Date?
        let endedAt: Date?
        let totalPausedSeconds: Double
        let statusRaw: String
        let sessionTypeRaw: String
        let notes: String?
        let hkWorkoutID: String?
        let planDayID: UUID?
    }

    struct CardioSessionLogDTO: Codable {
        let id: UUID
        let distance: Double?
        let durationSeconds: Int
        let avgPace: Double?
        let avgSpeed: Double?
        let calories: Double?
        let elevationGain: Double?
        let avgHeartRate: Int?
        let maxHeartRate: Int?
        let heartRateZonesData: Data?
        let avgCadence: Int?
        let strokeCount: Int?
        let strokeType: String?
        let swolf: Int?
        let laps: Int?
        let exerciseID: UUID?
        let sessionID: UUID
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
                targetValue: $0.targetValue,
                unit: $0.unit,
                metricKindRaw: $0.metricKindRaw,
                photoSlotsData: $0.photoSlotsData,
                sortOrder: $0.sortOrder,
                isArchived: $0.isArchived,
                createdAt: $0.createdDate,
                categoryID: $0.category?.id,
                parentID: $0.parent?.id,
                stoppedAt: $0.stoppedAt,
                healthKitTypeID: $0.healthKitTypeID,
                healthKitModeRaw: $0.healthKitModeRaw,
                aggregationModeRaw: $0.aggregationModeRaw,
                pausedParentId: $0.pausedParentId
            )
        }
        
        let logDTOs = logs.compactMap { log -> LogDTO? in
            guard let actID = log.activity?.id else { return nil }
            return LogDTO(
                id: log.id, date: log.date, statusRaw: log.statusRaw,
                value: log.value, photoFilename: log.photoFilename,
                photoFilenamesData: log.photoFilenamesData,
                note: log.note, skipReason: log.skipReason,
                timeSlotRaw: log.timeSlotRaw,
                completedAt: log.completedAt,
                source: log.source, activityID: actID
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

        // Goals
        let goals = try context.fetch(FetchDescriptor<Goal>())
        let goalLinks = try context.fetch(FetchDescriptor<GoalActivity>())

        let goalDTOs = goals.map { g in
            GoalDTO(id: g.id, title: g.title, icon: g.icon, hexColor: g.hexColor,
                    deadline: g.deadline, isArchived: false,
                    isManuallyPaused: g.isManuallyPaused,
                    createdAt: g.createdDate, sortOrder: g.sortOrder)
        }
        let goalActDTOs = goalLinks.compactMap { link -> GoalActivityDTO? in
            guard let gID = link.goal?.id, let aID = link.activity?.id else { return nil }
            return GoalActivityDTO(id: link.id, goalID: gID, activityID: aID,
                                   roleRaw: link.roleRaw, weight: link.weight,
                                   metricBaseline: link.metricBaseline,
                                   metricTarget: link.metricTarget,
                                   metricDirectionRaw: link.metricDirectionRaw)
        }

        // Workout Domain
        let allExercises = try context.fetch(FetchDescriptor<Exercise>())
        let exerciseDTOs = allExercises.map { e in
            ExerciseDTO(id: e.id, name: e.name, equipment: e.equipment,
                        exerciseTypeRaw: e.exerciseTypeRaw, aliasesData: e.aliasesData,
                        videoURLsData: e.videoURLsData, notes: e.notes,
                        distanceUnit: e.distanceUnit, paceUnit: e.paceUnit,
                        availableMetricsData: e.availableMetricsData,
                        isPreSeeded: e.isPreSeeded, createdAt: e.createdAt)
        }

        let allExMuscles = try context.fetch(FetchDescriptor<ExerciseMuscle>())
        let exMuscleDTOs = allExMuscles.compactMap { em -> ExerciseMuscleDTO? in
            guard let exID = em.exercise?.id else { return nil }
            return ExerciseMuscleDTO(id: em.id, exerciseID: exID,
                                     muscleGroupID: em.muscleGroupID,
                                     involvementScore: em.involvementScore)
        }

        let allMuscleGroups = try context.fetch(FetchDescriptor<MuscleGroup>())
        let mgDTOs = allMuscleGroups.map { mg in
            MuscleGroupDTO(id: mg.id, name: mg.name, parentID: mg.parentID,
                           sortOrder: mg.sortOrder, mevSets: mg.mevSets,
                           mavSets: mg.mavSets, mrvSets: mg.mrvSets,
                           isPreSeeded: mg.isPreSeeded)
        }

        let allPlans = try context.fetch(FetchDescriptor<WorkoutPlan>())
        let planDTOs = allPlans.map { p in
            WorkoutPlanDTO(id: p.id, name: p.name, planTypeRaw: p.planTypeRaw,
                           statusRaw: p.statusRaw, containerActivityID: p.containerActivityID,
                           createdAt: p.createdAt)
        }

        let allDays = try context.fetch(FetchDescriptor<WorkoutPlanDay>())
        let dayDTOs = allDays.compactMap { d -> WorkoutPlanDayDTO? in
            guard let planID = d.plan?.id else { return nil }
            return WorkoutPlanDayDTO(id: d.id, weekday: d.weekday, dayLabel: d.dayLabel,
                                     isLabelOverridden: d.isLabelOverridden, isRest: d.isRest,
                                     colorGroup: d.colorGroup, planID: planID)
        }

        let allStrPlanEx = try context.fetch(FetchDescriptor<StrengthPlanExercise>())
        let strPlanExDTOs = allStrPlanEx.compactMap { spe -> StrengthPlanExDTO? in
            guard let dayID = spe.planDay?.id else { return nil }
            return StrengthPlanExDTO(id: spe.id, targetSets: spe.targetSets, rir: spe.rir,
                                     sortOrder: spe.sortOrder, supersetGroup: spe.supersetGroup,
                                     exerciseID: spe.exercise?.id, planDayID: dayID)
        }

        let allCardioPlanEx = try context.fetch(FetchDescriptor<CardioPlanExercise>())
        let cardioPlanExDTOs = allCardioPlanEx.compactMap { cpe -> CardioPlanExDTO? in
            guard let dayID = cpe.planDay?.id else { return nil }
            return CardioPlanExDTO(id: cpe.id, sessionTypeRaw: cpe.sessionTypeRaw,
                                   targetDistance: cpe.targetDistance,
                                   targetDurationMin: cpe.targetDurationMin,
                                   sessionParamsData: cpe.sessionParamsData,
                                   sortOrder: cpe.sortOrder, exerciseID: cpe.exercise?.id,
                                   planDayID: dayID)
        }

        let allStrSessions = try context.fetch(FetchDescriptor<StrengthSession>())
        let strSessionDTOs = allStrSessions.map { s in
            StrengthSessionDTO(id: s.id, planName: s.planName, dayLabel: s.dayLabel,
                               weekday: s.weekday, date: s.date, startedAt: s.startedAt,
                               pausedAt: s.pausedAt, endedAt: s.endedAt,
                               totalPausedSeconds: s.totalPausedSeconds, statusRaw: s.statusRaw,
                               notes: s.notes, resumedAtSetCount: s.resumedAtSetCount,
                               resumedAtEndedAt: s.resumedAtEndedAt,
                               resumedAtPausedSeconds: s.resumedAtPausedSeconds,
                               planDayID: s.planDay?.id)
        }

        let allSetLogs = try context.fetch(FetchDescriptor<WorkoutSetLog>())
        let setLogDTOs = allSetLogs.compactMap { sl -> WorkoutSetLogDTO? in
            guard let sessionID = sl.session?.id else { return nil }
            return WorkoutSetLogDTO(id: sl.id, setNumber: sl.setNumber, reps: sl.reps,
                                    weight: sl.weight, durationSeconds: sl.durationSeconds,
                                    isWarmup: sl.isWarmup, completedAt: sl.completedAt,
                                    exerciseID: sl.exercise?.id, sessionID: sessionID)
        }

        let allCardioSessions = try context.fetch(FetchDescriptor<CardioSession>())
        let cardioSessionDTOs = allCardioSessions.map { cs in
            CardioSessionDTO(id: cs.id, planName: cs.planName, dayLabel: cs.dayLabel,
                             weekday: cs.weekday, date: cs.date, startedAt: cs.startedAt,
                             pausedAt: cs.pausedAt, endedAt: cs.endedAt,
                             totalPausedSeconds: cs.totalPausedSeconds, statusRaw: cs.statusRaw,
                             sessionTypeRaw: cs.sessionTypeRaw, notes: cs.notes,
                             hkWorkoutID: cs.hkWorkoutID, planDayID: cs.planDay?.id)
        }

        let allCardioLogs = try context.fetch(FetchDescriptor<CardioSessionLog>())
        let cardioLogDTOs = allCardioLogs.compactMap { cl -> CardioSessionLogDTO? in
            guard let sessionID = cl.session?.id else { return nil }
            return CardioSessionLogDTO(id: cl.id, distance: cl.distance,
                                       durationSeconds: cl.durationSeconds, avgPace: cl.avgPace,
                                       avgSpeed: cl.avgSpeed, calories: cl.calories,
                                       elevationGain: cl.elevationGain, avgHeartRate: cl.avgHeartRate,
                                       maxHeartRate: cl.maxHeartRate, heartRateZonesData: cl.heartRateZonesData,
                                       avgCadence: cl.avgCadence, strokeCount: cl.strokeCount,
                                       strokeType: cl.strokeType, swolf: cl.swolf, laps: cl.laps,
                                       exerciseID: cl.exerciseID, sessionID: sessionID)
        }

        // Create Package
        var package = ExportPackage(
            version: "2.0",
            timestamp: Date(),
            categories: catDTOs,
            activities: actDTOs,
            logs: logDTOs,
            vacationDays: vacDTOs,
            configSnapshots: snapDTOs,
            goals: goalDTOs,
            goalActivities: goalActDTOs
        )
        package.exercises = exerciseDTOs
        package.exerciseMuscles = exMuscleDTOs
        package.muscleGroups = mgDTOs
        package.workoutPlans = planDTOs
        package.workoutPlanDays = dayDTOs
        package.strengthPlanExercises = strPlanExDTOs
        package.cardioPlanExercises = cardioPlanExDTOs
        package.strengthSessions = strSessionDTOs
        package.workoutSetLogs = setLogDTOs
        package.cardioSessions = cardioSessionDTOs
        package.cardioSessionLogs = cardioLogDTOs
        
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

        // Clear workout domain (children first)
        let existingSetLogs = try context.fetch(FetchDescriptor<WorkoutSetLog>())
        for sl in existingSetLogs { context.delete(sl) }
        let existingCardioLogs = try context.fetch(FetchDescriptor<CardioSessionLog>())
        for cl in existingCardioLogs { context.delete(cl) }
        let existingStrSessions = try context.fetch(FetchDescriptor<StrengthSession>())
        for ss in existingStrSessions { context.delete(ss) }
        let existingCardioSessions = try context.fetch(FetchDescriptor<CardioSession>())
        for cs in existingCardioSessions { context.delete(cs) }
        let existingStrPlanEx = try context.fetch(FetchDescriptor<StrengthPlanExercise>())
        for spe in existingStrPlanEx { context.delete(spe) }
        let existingCardioPlanEx = try context.fetch(FetchDescriptor<CardioPlanExercise>())
        for cpe in existingCardioPlanEx { context.delete(cpe) }
        let existingPlanDays = try context.fetch(FetchDescriptor<WorkoutPlanDay>())
        for pd in existingPlanDays { context.delete(pd) }
        let existingPlans = try context.fetch(FetchDescriptor<WorkoutPlan>())
        for wp in existingPlans { context.delete(wp) }
        let existingExMuscles = try context.fetch(FetchDescriptor<ExerciseMuscle>())
        for em in existingExMuscles { context.delete(em) }
        let existingExercises = try context.fetch(FetchDescriptor<Exercise>())
        for ex in existingExercises { context.delete(ex) }
        let existingMG = try context.fetch(FetchDescriptor<MuscleGroup>())
        for mg in existingMG { context.delete(mg) }

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
            act.targetValue = dto.targetValue
            act.unit = dto.unit
            act.metricKindRaw = dto.metricKindRaw
            act.sortOrder = dto.sortOrder
            act.isArchived = dto.isArchived
            act.createdAt = dto.createdAt
            // Backward compat: legacy exports have isArchived but no stoppedAt
            if dto.isArchived && dto.stoppedAt == nil {
                act.stoppedAt = dto.createdAt
            } else {
                act.stoppedAt = dto.stoppedAt
            }
            act.pausedParentId = dto.pausedParentId
            act.healthKitTypeID = dto.healthKitTypeID
            act.healthKitModeRaw = dto.healthKitModeRaw
            act.aggregationModeRaw = dto.aggregationModeRaw
            act.photoSlotsData = dto.photoSlotsData
            
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
            log.photoFilenamesData = dto.photoFilenamesData
            log.note = dto.note
            log.skipReason = dto.skipReason
            log.timeSlotRaw = dto.timeSlotRaw
            log.completedAt = dto.completedAt
            log.source = dto.source
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

        // Clear existing goals
        let existingGoals = try context.fetch(FetchDescriptor<Goal>())
        for g in existingGoals { context.delete(g) }
        let existingLinks = try context.fetch(FetchDescriptor<GoalActivity>())
        for l in existingLinks { context.delete(l) }

        // Insert Goals
        var goalMap: [UUID: Goal] = [:]
        if let goalDTOs = package.goals {
            for dto in goalDTOs {
                let g = Goal(title: dto.title, icon: dto.icon, hexColor: dto.hexColor,
                             sortOrder: dto.sortOrder)
                g.id = dto.id
                g.deadline = dto.deadline
                g.isManuallyPaused = dto.isManuallyPaused
                g.createdAt = dto.createdAt
                context.insert(g)
                goalMap[dto.id] = g
            }
        }

        // Insert Goal-Activity Links
        if let linkDTOs = package.goalActivities {
            for dto in linkDTOs {
                guard let goal = goalMap[dto.goalID],
                      let act = activityMap[dto.activityID] else { continue }
                let role = GoalActivityRole(rawValue: dto.roleRaw) ?? .activity
                let link = GoalActivity(goal: goal, activity: act, role: role, weight: dto.weight)
                link.id = dto.id
                link.metricBaseline = dto.metricBaseline
                link.metricTarget = dto.metricTarget
                link.metricDirectionRaw = dto.metricDirectionRaw
                context.insert(link)
            }
        }

        // MARK: - Import Workout Domain

        // Muscle Groups
        var muscleGroupMap: [UUID: MuscleGroup] = [:]
        if let mgDTOs = package.muscleGroups {
            for dto in mgDTOs {
                let mg = MuscleGroup(name: dto.name, parentID: dto.parentID,
                                     sortOrder: dto.sortOrder, mevSets: dto.mevSets,
                                     mavSets: dto.mavSets, mrvSets: dto.mrvSets,
                                     isPreSeeded: dto.isPreSeeded)
                mg.id = dto.id
                context.insert(mg)
                muscleGroupMap[dto.id] = mg
            }
        }

        // Exercises
        var exerciseMap: [UUID: Exercise] = [:]
        if let exDTOs = package.exercises {
            for dto in exDTOs {
                let ex = Exercise(name: dto.name, equipment: dto.equipment,
                                  type: ExerciseType(rawValue: dto.exerciseTypeRaw) ?? .strength,
                                  isPreSeeded: dto.isPreSeeded)
                ex.id = dto.id
                ex.aliasesData = dto.aliasesData
                ex.videoURLsData = dto.videoURLsData
                ex.notes = dto.notes
                ex.distanceUnit = dto.distanceUnit
                ex.paceUnit = dto.paceUnit
                ex.availableMetricsData = dto.availableMetricsData
                ex.createdAt = dto.createdAt
                context.insert(ex)
                exerciseMap[dto.id] = ex
            }
        }

        // Exercise-Muscle links
        if let emDTOs = package.exerciseMuscles {
            for dto in emDTOs {
                guard let ex = exerciseMap[dto.exerciseID] else { continue }
                let em = ExerciseMuscle(muscleGroupID: dto.muscleGroupID ?? UUID(),
                                        score: dto.involvementScore)
                em.id = dto.id
                em.exercise = ex
                em.muscleGroupID = dto.muscleGroupID
                context.insert(em)
            }
        }

        // Workout Plans
        var planMap: [UUID: WorkoutPlan] = [:]
        if let planDTOs = package.workoutPlans {
            for dto in planDTOs {
                let p = WorkoutPlan(name: dto.name,
                                    planType: ExerciseType(rawValue: dto.planTypeRaw) ?? .strength)
                p.id = dto.id
                p.statusRaw = dto.statusRaw
                p.containerActivityID = dto.containerActivityID
                p.createdAt = dto.createdAt
                context.insert(p)
                planMap[dto.id] = p
            }
        }

        // Workout Plan Days
        var dayMap: [UUID: WorkoutPlanDay] = [:]
        if let dayDTOs = package.workoutPlanDays {
            for dto in dayDTOs {
                let d = WorkoutPlanDay(weekday: dto.weekday, plan: planMap[dto.planID])
                d.id = dto.id
                d.dayLabel = dto.dayLabel
                d.isLabelOverridden = dto.isLabelOverridden
                d.isRest = dto.isRest
                d.colorGroup = dto.colorGroup
                context.insert(d)
                dayMap[dto.id] = d
            }
        }

        // Strength Plan Exercises
        if let speDTOs = package.strengthPlanExercises {
            for dto in speDTOs {
                guard let day = dayMap[dto.planDayID] else { continue }
                let ex = dto.exerciseID.flatMap { exerciseMap[$0] }
                let spe = StrengthPlanExercise(exercise: ex ?? Exercise(name: "Unknown", equipment: "?"),
                                               targetSets: dto.targetSets, rir: dto.rir,
                                               sortOrder: dto.sortOrder)
                spe.id = dto.id
                spe.supersetGroup = dto.supersetGroup
                spe.exercise = ex
                spe.planDay = day
                context.insert(spe)
            }
        }

        // Cardio Plan Exercises
        if let cpeDTOs = package.cardioPlanExercises {
            for dto in cpeDTOs {
                guard let day = dayMap[dto.planDayID] else { continue }
                let ex = dto.exerciseID.flatMap { exerciseMap[$0] }
                let cpe = CardioPlanExercise(exercise: ex ?? Exercise(name: "Unknown", equipment: "?"),
                                             sessionType: CardioSessionType(rawValue: dto.sessionTypeRaw) ?? .free,
                                             sortOrder: dto.sortOrder)
                cpe.id = dto.id
                cpe.targetDistance = dto.targetDistance
                cpe.targetDurationMin = dto.targetDurationMin
                cpe.sessionParamsData = dto.sessionParamsData
                cpe.exercise = ex
                cpe.planDay = day
                context.insert(cpe)
            }
        }

        // Strength Sessions
        var strSessionMap: [UUID: StrengthSession] = [:]
        if let ssDTOs = package.strengthSessions {
            for dto in ssDTOs {
                let s = StrengthSession(planName: dto.planName, dayLabel: dto.dayLabel,
                                        weekday: dto.weekday,
                                        planDay: dto.planDayID.flatMap { dayMap[$0] })
                s.id = dto.id
                s.date = dto.date
                s.startedAt = dto.startedAt
                s.pausedAt = dto.pausedAt
                s.endedAt = dto.endedAt
                s.totalPausedSeconds = dto.totalPausedSeconds
                s.statusRaw = dto.statusRaw
                s.notes = dto.notes
                s.resumedAtSetCount = dto.resumedAtSetCount
                s.resumedAtEndedAt = dto.resumedAtEndedAt
                s.resumedAtPausedSeconds = dto.resumedAtPausedSeconds
                context.insert(s)
                strSessionMap[dto.id] = s
            }
        }

        // Workout Set Logs
        if let slDTOs = package.workoutSetLogs {
            for dto in slDTOs {
                guard let session = strSessionMap[dto.sessionID] else { continue }
                let ex = dto.exerciseID.flatMap { exerciseMap[$0] }
                    ?? Exercise(name: "Unknown", equipment: "?")
                let sl = WorkoutSetLog(exercise: ex, setNumber: dto.setNumber,
                                       reps: dto.reps, weight: dto.weight,
                                       isWarmup: dto.isWarmup)
                sl.id = dto.id
                sl.durationSeconds = dto.durationSeconds
                sl.completedAt = dto.completedAt
                sl.session = session
                context.insert(sl)
            }
        }

        // Cardio Sessions
        var cardioSessionMap: [UUID: CardioSession] = [:]
        if let csDTOs = package.cardioSessions {
            for dto in csDTOs {
                let cs = CardioSession(planName: dto.planName, dayLabel: dto.dayLabel,
                                       weekday: dto.weekday,
                                       sessionType: CardioSessionType(rawValue: dto.sessionTypeRaw) ?? .free,
                                       planDay: dto.planDayID.flatMap { dayMap[$0] })
                cs.id = dto.id
                cs.date = dto.date
                cs.startedAt = dto.startedAt
                cs.pausedAt = dto.pausedAt
                cs.endedAt = dto.endedAt
                cs.totalPausedSeconds = dto.totalPausedSeconds
                cs.statusRaw = dto.statusRaw
                cs.notes = dto.notes
                cs.hkWorkoutID = dto.hkWorkoutID
                context.insert(cs)
                cardioSessionMap[dto.id] = cs
            }
        }

        // Cardio Session Logs
        if let clDTOs = package.cardioSessionLogs {
            for dto in clDTOs {
                guard let session = cardioSessionMap[dto.sessionID] else { continue }
                let cl = CardioSessionLog(exerciseID: dto.exerciseID)
                cl.id = dto.id
                cl.distance = dto.distance
                cl.durationSeconds = dto.durationSeconds
                cl.avgPace = dto.avgPace
                cl.avgSpeed = dto.avgSpeed
                cl.calories = dto.calories
                cl.elevationGain = dto.elevationGain
                cl.avgHeartRate = dto.avgHeartRate
                cl.maxHeartRate = dto.maxHeartRate
                cl.heartRateZonesData = dto.heartRateZonesData
                cl.avgCadence = dto.avgCadence
                cl.strokeCount = dto.strokeCount
                cl.strokeType = dto.strokeType
                cl.swolf = dto.swolf
                cl.laps = dto.laps
                cl.session = session
                context.insert(cl)
            }
        }

        try context.save()
    }
}
