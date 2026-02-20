import Foundation
import HealthKit

/// Protocol for HealthKit operations — enables mocking for tests
protocol HealthKitServiceProtocol {
    func requestAuthorization(for types: Set<HKQuantityTypeIdentifier>) async throws
    func readLatestValue(for type: HKQuantityTypeIdentifier, unit: HKUnit, excludingOwnApp: Bool) async throws -> Double?
    func readTotalToday(for type: HKQuantityTypeIdentifier, unit: HKUnit, excludingOwnApp: Bool) async throws -> Double
    func writeSample(type: HKQuantityTypeIdentifier, value: Double, unit: HKUnit, date: Date) async throws
    var isAvailable: Bool { get }
}

final class HealthKitService: HealthKitServiceProtocol {
    static let shared = HealthKitService()

    private let healthStore = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Authorization

    func requestAuthorization(for types: Set<HKQuantityTypeIdentifier>) async throws {
        guard isAvailable else { return }

        let shareTypes = Set(types.compactMap { HKQuantityType.quantityType(forIdentifier: $0) })
        let readTypes: Set<HKObjectType> = Set(types.compactMap { HKQuantityType.quantityType(forIdentifier: $0) })

        guard !shareTypes.isEmpty || !readTypes.isEmpty else { return }

        try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    // MARK: - Read

    func readLatestValue(for type: HKQuantityTypeIdentifier, unit: HKUnit, excludingOwnApp: Bool = false) async throws -> Double? {
        guard isAvailable,
              let quantityType = HKQuantityType.quantityType(forIdentifier: type)
        else { return nil }

        var subPredicates: [NSPredicate] = [
            HKQuery.predicateForSamples(withStart: Date().startOfDay, end: Date(), options: .strictStartDate)
        ]
        if excludingOwnApp, let bundleId = Bundle.main.bundleIdentifier {
            let source = HKSource.default()
            subPredicates.append(NSCompoundPredicate(notPredicateWithSubpredicate:
                HKQuery.predicateForObjects(from: Set([source]))
            ))
        }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subPredicates)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    func readTotalToday(for type: HKQuantityTypeIdentifier, unit: HKUnit, excludingOwnApp: Bool = false) async throws -> Double {
        guard isAvailable,
              let quantityType = HKQuantityType.quantityType(forIdentifier: type)
        else { return 0 }

        var subPredicates: [NSPredicate] = [
            HKQuery.predicateForSamples(
                withStart: Date().startOfDay,
                end: Date(),
                options: .strictStartDate
            )
        ]
        if excludingOwnApp, let bundleId = Bundle.main.bundleIdentifier {
            let source = HKSource.default()
            subPredicates.append(NSCompoundPredicate(notPredicateWithSubpredicate:
                HKQuery.predicateForObjects(from: Set([source]))
            ))
        }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subPredicates)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let total = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: total)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Write

    func writeSample(type: HKQuantityTypeIdentifier, value: Double, unit: HKUnit, date: Date) async throws {
        guard isAvailable,
              let quantityType = HKQuantityType.quantityType(forIdentifier: type)
        else { return }

        let quantity = HKQuantity(unit: unit, doubleValue: value)
        let sample = HKQuantitySample(
            type: quantityType,
            quantity: quantity,
            start: date,
            end: date
        )

        try await healthStore.save(sample)
    }

    // MARK: - Mapping helpers

    /// Maps a short HealthKit type name (from picker) to the proper HKQuantityTypeIdentifier.
    /// The picker stores short names like "dietaryWater" but HK needs "HKQuantityTypeIdentifierDietaryWater".
    static func identifierFrom(_ raw: String) -> HKQuantityTypeIdentifier? {
        if let match = allTypes.first(where: { $0.key == raw }) {
            return match.id
        }
        // Fall back to direct rawValue (for full HK identifiers)
        let id = HKQuantityTypeIdentifier(rawValue: raw)
        guard HKQuantityType.quantityType(forIdentifier: id) != nil else { return nil }
        return id
    }

    /// Returns the correct HKUnit for a given type identifier.
    static func unitFor(type: HKQuantityTypeIdentifier) -> HKUnit {
        allTypes.first { $0.id == type }?.unit ?? .count()
    }

    /// Single source of truth for all supported HealthKit types.
    /// `key` is the short string stored in Activity.healthKitTypeID.
    /// `category` groups them in the picker UI.
    struct HKTypeInfo {
        let key: String
        let name: String
        let category: String
        let id: HKQuantityTypeIdentifier
        let unit: HKUnit
    }

    static let allTypes: [HKTypeInfo] = [
        // Activity & Fitness
        HKTypeInfo(key: "stepCount",              name: "Steps",                   category: "Activity",    id: .stepCount,              unit: .count()),
        HKTypeInfo(key: "distanceWalkingRunning",  name: "Walking + Running (km)",  category: "Activity",    id: .distanceWalkingRunning, unit: .meterUnit(with: .kilo)),
        HKTypeInfo(key: "distanceCycling",         name: "Cycling Distance (km)",   category: "Activity",    id: .distanceCycling,        unit: .meterUnit(with: .kilo)),
        HKTypeInfo(key: "distanceSwimming",        name: "Swimming Distance (m)",   category: "Activity",    id: .distanceSwimming,       unit: .meter()),
        HKTypeInfo(key: "activeEnergyBurned",      name: "Active Calories",         category: "Activity",    id: .activeEnergyBurned,     unit: .kilocalorie()),
        HKTypeInfo(key: "basalEnergyBurned",       name: "Resting Calories",        category: "Activity",    id: .basalEnergyBurned,      unit: .kilocalorie()),
        HKTypeInfo(key: "appleExerciseTime",       name: "Exercise Minutes",        category: "Activity",    id: .appleExerciseTime,      unit: .minute()),
        HKTypeInfo(key: "appleStandTime",          name: "Stand Minutes",           category: "Activity",    id: .appleStandTime,         unit: .minute()),
        HKTypeInfo(key: "flightsClimbed",          name: "Flights Climbed",         category: "Activity",    id: .flightsClimbed,         unit: .count()),
        HKTypeInfo(key: "appleWalkingSteadiness",  name: "Walking Steadiness (%)",  category: "Activity",    id: .appleWalkingSteadiness, unit: .percent()),
        HKTypeInfo(key: "walkingSpeed",            name: "Walking Speed (km/h)",    category: "Activity",    id: .walkingSpeed,           unit: HKUnit.meter().unitDivided(by: .second())),
        HKTypeInfo(key: "walkingStepLength",       name: "Step Length (cm)",        category: "Activity",    id: .walkingStepLength,      unit: .meterUnit(with: .centi)),

        // Body Measurements
        HKTypeInfo(key: "bodyMass",                name: "Weight (kg)",             category: "Body",        id: .bodyMass,               unit: .gramUnit(with: .kilo)),
        HKTypeInfo(key: "bodyFatPercentage",       name: "Body Fat (%)",            category: "Body",        id: .bodyFatPercentage,      unit: .percent()),
        HKTypeInfo(key: "bodyMassIndex",           name: "BMI",                     category: "Body",        id: .bodyMassIndex,          unit: .count()),
        HKTypeInfo(key: "leanBodyMass",            name: "Lean Body Mass (kg)",     category: "Body",        id: .leanBodyMass,           unit: .gramUnit(with: .kilo)),
        HKTypeInfo(key: "height",                  name: "Height (cm)",             category: "Body",        id: .height,                 unit: .meterUnit(with: .centi)),
        HKTypeInfo(key: "waistCircumference",      name: "Waist (cm)",              category: "Body",        id: .waistCircumference,     unit: .meterUnit(with: .centi)),

        // Heart
        HKTypeInfo(key: "heartRate",               name: "Heart Rate (bpm)",        category: "Heart",       id: .heartRate,              unit: HKUnit.count().unitDivided(by: .minute())),
        HKTypeInfo(key: "restingHeartRate",         name: "Resting Heart Rate",      category: "Heart",       id: .restingHeartRate,       unit: HKUnit.count().unitDivided(by: .minute())),
        HKTypeInfo(key: "walkingHeartRateAverage",  name: "Walking HR Average",      category: "Heart",       id: .walkingHeartRateAverage, unit: HKUnit.count().unitDivided(by: .minute())),
        HKTypeInfo(key: "heartRateVariabilitySDNN", name: "HRV (ms)",               category: "Heart",       id: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli)),
        HKTypeInfo(key: "vo2Max",                  name: "VO₂ Max",                 category: "Heart",       id: .vo2Max,                 unit: HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))),
        HKTypeInfo(key: "oxygenSaturation",        name: "Blood Oxygen (%)",        category: "Heart",       id: .oxygenSaturation,       unit: .percent()),
        HKTypeInfo(key: "bloodPressureSystolic",   name: "Blood Pressure (sys)",    category: "Heart",       id: .bloodPressureSystolic,  unit: .millimeterOfMercury()),
        HKTypeInfo(key: "bloodPressureDiastolic",  name: "Blood Pressure (dia)",    category: "Heart",       id: .bloodPressureDiastolic, unit: .millimeterOfMercury()),

        // Nutrition
        HKTypeInfo(key: "dietaryWater",            name: "Water (ml)",              category: "Nutrition",   id: .dietaryWater,           unit: .literUnit(with: .milli)),
        HKTypeInfo(key: "dietaryEnergyConsumed",   name: "Calories Eaten",          category: "Nutrition",   id: .dietaryEnergyConsumed,  unit: .kilocalorie()),
        HKTypeInfo(key: "dietaryProtein",          name: "Protein (g)",             category: "Nutrition",   id: .dietaryProtein,         unit: .gram()),
        HKTypeInfo(key: "dietaryCarbohydrates",    name: "Carbs (g)",               category: "Nutrition",   id: .dietaryCarbohydrates,   unit: .gram()),
        HKTypeInfo(key: "dietaryFatTotal",         name: "Fat (g)",                 category: "Nutrition",   id: .dietaryFatTotal,        unit: .gram()),
        HKTypeInfo(key: "dietaryCaffeine",         name: "Caffeine (mg)",           category: "Nutrition",   id: .dietaryCaffeine,        unit: .gramUnit(with: .milli)),
        HKTypeInfo(key: "dietaryFiber",            name: "Fiber (g)",               category: "Nutrition",   id: .dietaryFiber,           unit: .gram()),
        HKTypeInfo(key: "dietarySugar",            name: "Sugar (g)",               category: "Nutrition",   id: .dietarySugar,           unit: .gram()),

        // Respiratory
        HKTypeInfo(key: "respiratoryRate",         name: "Respiratory Rate",        category: "Respiratory", id: .respiratoryRate,        unit: HKUnit.count().unitDivided(by: .minute())),

        // Other
        HKTypeInfo(key: "bloodGlucose",            name: "Blood Glucose (mg/dL)",   category: "Other",       id: .bloodGlucose,           unit: HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))),
        HKTypeInfo(key: "bodyTemperature",         name: "Body Temperature (°C)",   category: "Other",       id: .bodyTemperature,        unit: .degreeCelsius()),
    ]

    /// Grouped by category for the picker UI
    static var typesByCategory: [(category: String, types: [HKTypeInfo])] {
        let grouped = Dictionary(grouping: allTypes, by: \.category)
        let order = ["Activity", "Body", "Heart", "Nutrition", "Respiratory", "Other"]
        return order.compactMap { cat in
            guard let types = grouped[cat] else { return nil }
            return (category: cat, types: types)
        }
    }

    // MARK: - Workout Builder (Cardio Sessions)

    /// Requests authorization for workout-related types (HR, distance, calories, etc.)
    func requestWorkoutAuthorization() async throws {
        guard isAvailable else { return }

        var readTypes = Set<HKObjectType>()
        var shareTypes = Set<HKSampleType>()

        // Workout type
        let workoutType = HKObjectType.workoutType()
        readTypes.insert(workoutType)
        shareTypes.insert(workoutType)

        // Quantity types
        let quantityIDs: [HKQuantityTypeIdentifier] = [
            .heartRate, .distanceWalkingRunning, .distanceCycling,
            .distanceSwimming, .activeEnergyBurned, .stepCount
        ]
        for id in quantityIDs {
            if let qt = HKQuantityType.quantityType(forIdentifier: id) {
                readTypes.insert(qt)
            }
        }

        try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    /// Creates and begins an HKWorkoutBuilder for the given activity type.
    func createWorkoutBuilder(activityType: HKWorkoutActivityType) -> HKWorkoutBuilder {
        let config = HKWorkoutConfiguration()
        config.activityType = activityType
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())
        return builder
    }

    /// Starts the workout builder's data collection.
    func beginWorkoutBuilder(_ builder: HKWorkoutBuilder) async throws {
        try await builder.beginCollection(at: Date())
    }

    /// Ends and saves the workout via builder.
    func finishWorkoutBuilder(_ builder: HKWorkoutBuilder) async throws -> HKWorkout? {
        try await builder.endCollection(at: Date())
        let results = try await builder.finishWorkout()
        return results
    }

    /// Starts an anchored query for live heart rate updates.
    func startHeartRateQuery(from startDate: Date, handler: @escaping (Double) -> Void) -> HKQuery? {
        guard isAvailable,
              let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
        let hrUnit = HKUnit.count().unitDivided(by: .minute())

        let query = HKAnchoredObjectQuery(
            type: hrType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { _, samples, _, _, _ in
            guard let quantitySamples = samples as? [HKQuantitySample],
                  let latest = quantitySamples.last else { return }
            let bpm = latest.quantity.doubleValue(for: hrUnit)
            DispatchQueue.main.async { handler(bpm) }
        }

        query.updateHandler = { _, samples, _, _, _ in
            guard let quantitySamples = samples as? [HKQuantitySample],
                  let latest = quantitySamples.last else { return }
            let bpm = latest.quantity.doubleValue(for: hrUnit)
            DispatchQueue.main.async { handler(bpm) }
        }

        healthStore.execute(query)
        return query
    }

    /// Starts an anchored query for live distance updates (cumulative).
    func startDistanceQuery(type: HKQuantityTypeIdentifier, from startDate: Date, handler: @escaping (Double) -> Void) -> HKQuery? {
        guard isAvailable,
              let distType = HKQuantityType.quantityType(forIdentifier: type) else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
        let unit = HKUnit.meter()

        let query = HKAnchoredObjectQuery(
            type: distType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { _, samples, _, _, _ in
            let total = (samples as? [HKQuantitySample])?.reduce(0.0) {
                $0 + $1.quantity.doubleValue(for: unit)
            } ?? 0
            DispatchQueue.main.async { handler(total) }
        }

        query.updateHandler = { _, samples, _, _, _ in
            let added = (samples as? [HKQuantitySample])?.reduce(0.0) {
                $0 + $1.quantity.doubleValue(for: unit)
            } ?? 0
            if added > 0 {
                DispatchQueue.main.async { handler(added) }
            }
        }

        healthStore.execute(query)
        return query
    }

    /// Stops an active HK query.
    func stopQuery(_ query: HKQuery) {
        healthStore.stop(query)
    }

    /// Maps exercise name to HKWorkoutActivityType.
    static func activityType(for exerciseName: String) -> HKWorkoutActivityType {
        let name = exerciseName.lowercased()
        if name.contains("run") { return .running }
        if name.contains("swim") { return .swimming }
        if name.contains("cycl") || name.contains("bike") { return .cycling }
        if name.contains("row") { return .rowing }
        if name.contains("walk") { return .walking }
        if name.contains("hik") { return .hiking }
        if name.contains("elliptical") { return .elliptical }
        return .other
    }

    /// Maps HKWorkoutActivityType to the right distance quantity type.
    static func distanceType(for activityType: HKWorkoutActivityType) -> HKQuantityTypeIdentifier {
        switch activityType {
        case .swimming: return .distanceSwimming
        case .cycling: return .distanceCycling
        default: return .distanceWalkingRunning
        }
    }
}

