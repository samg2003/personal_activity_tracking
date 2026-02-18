import Foundation
import HealthKit

/// Protocol for HealthKit operations — enables mocking for tests
protocol HealthKitServiceProtocol {
    func requestAuthorization(for types: Set<HKQuantityTypeIdentifier>) async throws
    func readLatestValue(for type: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double?
    func readTotalToday(for type: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double
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

    func readLatestValue(for type: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double? {
        guard isAvailable,
              let quantityType = HKQuantityType.quantityType(forIdentifier: type)
        else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: Date().startOfDay, end: Date(), options: .strictStartDate)
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

    func readTotalToday(for type: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double {
        guard isAvailable,
              let quantityType = HKQuantityType.quantityType(forIdentifier: type)
        else { return 0 }

        let predicate = HKQuery.predicateForSamples(
            withStart: Date().startOfDay,
            end: Date(),
            options: .strictStartDate
        )

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

    /// Maps a HealthKit type identifier string to HKQuantityTypeIdentifier
    static func identifierFrom(_ raw: String) -> HKQuantityTypeIdentifier? {
        HKQuantityTypeIdentifier(rawValue: raw)
    }

    /// Returns the correct HKUnit for a given type identifier by looking up commonTypes.
    static func unitFor(type: HKQuantityTypeIdentifier) -> HKUnit {
        commonTypes.first { $0.id == type }?.unit ?? .count()
    }

    /// Common types for the picker
    static let commonTypes: [(name: String, id: HKQuantityTypeIdentifier, unit: HKUnit)] = [
        ("Steps", .stepCount, .count()),
        ("Water (ml)", .dietaryWater, .literUnit(with: .milli)),
        ("Weight (kg)", .bodyMass, .gramUnit(with: .kilo)),
        ("Body Fat (%)", .bodyFatPercentage, .percent()),
        ("Heart Rate", .heartRate, HKUnit.count().unitDivided(by: .minute())),
        ("Sleep (hrs)", .appleExerciseTime, .hour()), // placeholder until SleepAnalysis
        ("Calories Burned", .activeEnergyBurned, .kilocalorie()),
        ("Walking Distance (km)", .distanceWalkingRunning, .meterUnit(with: .kilo)),
    ]

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

