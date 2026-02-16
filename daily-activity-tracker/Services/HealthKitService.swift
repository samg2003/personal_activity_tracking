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
}
