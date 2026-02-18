import Foundation
import SwiftData
import HealthKit
import Combine
import CoreLocation

/// Manages cardio session lifecycle: start, pause, resume, finish, abandon.
/// Integrates with HealthKit for workout builder and live metric queries.
/// Uses CLLocationManager (GPS) for real-time distance tracking.
final class CardioSessionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var modelContext: ModelContext?
    private let hkService = HealthKitService.shared

    // Live metric state — published for SwiftUI binding
    @Published var currentHeartRate: Double = 0
    @Published var totalDistanceMeters: Double = 0
    @Published var estimatedCalories: Double = 0

    // Active HK queries
    private var hrQuery: HKQuery?
    private var distanceQuery: HKQuery?
    private var workoutBuilder: HKWorkoutBuilder?
    private var hkActivityType: HKWorkoutActivityType = .other

    // GPS distance tracking
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var trackingDistance = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        locationManager.distanceFilter = 5 // Update every 5 meters
        locationManager.allowsBackgroundLocationUpdates = false
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        locationManager.distanceFilter = 5
        locationManager.allowsBackgroundLocationUpdates = false
    }

    /// Replaces the placeholder context with the real one from the environment.
    func updateModelContext(_ ctx: ModelContext) {
        self.modelContext = ctx
    }

    // MARK: - Session Lifecycle

    /// Starts a new cardio session for the given plan exercise.
    @discardableResult
    func startSession(for planDay: WorkoutPlanDay, cardioPlanExercise: CardioPlanExercise) -> CardioSession {
        let plan = planDay.plan
        let exerciseName = cardioPlanExercise.exercise?.name ?? ""
        hkActivityType = HealthKitService.activityType(for: exerciseName)

        let session = CardioSession(
            planName: plan?.name ?? "Cardio",
            dayLabel: planDay.dayLabel,
            weekday: planDay.weekday,
            sessionType: cardioPlanExercise.sessionType,
            planDay: planDay
        )
        modelContext?.insert(session)
        try? modelContext?.save()

        let startDate = session.startedAt

        // Start GPS distance tracking (synchronous, main thread)
        startGPSTracking()

        // Start HealthKit queries in background (may hang on auth)
        Task {
            await self.startHealthKitTracking(startDate: startDate)
        }

        return session
    }

    func pauseSession(_ session: CardioSession) {
        guard session.status == .inProgress else { return }
        session.pausedAt = Date()
        session.status = .paused
        try? modelContext?.save()
    }

    func resumeSession(_ session: CardioSession) {
        guard session.status == .paused, let pausedAt = session.pausedAt else { return }
        session.totalPausedSeconds += Date().timeIntervalSince(pausedAt)
        session.pausedAt = nil
        session.status = .inProgress
        try? modelContext?.save()
    }

    /// Finishes the session: stops HK queries, saves workout, populates log, auto-completes shell.
    func finishSession(_ session: CardioSession, cardioPlanExercise: CardioPlanExercise?) {
        if session.status == .paused, let pausedAt = session.pausedAt {
            session.totalPausedSeconds += Date().timeIntervalSince(pausedAt)
            session.pausedAt = nil
        }

        session.endedAt = Date()
        session.status = .completed

        // Populate session log from accumulated metrics
        let log = createSessionLog(for: session, exercise: cardioPlanExercise?.exercise)
        session.logs.append(log)
        modelContext?.insert(log)

        // Auto-completion bridge
        autoCompleteShell(for: session, cardioPlanExercise: cardioPlanExercise)

        // HealthKit finalization (async, best-effort)
        Task { @MainActor in
            await finishHealthKitTracking(session: session)
        }

        try? modelContext?.save()
    }

    func abandonSession(_ session: CardioSession) {
        if session.status == .paused, let pausedAt = session.pausedAt {
            session.totalPausedSeconds += Date().timeIntervalSince(pausedAt)
            session.pausedAt = nil
        }

        session.endedAt = Date()
        session.status = .abandoned
        stopHealthKitQueries()
        try? modelContext?.save()
    }

    // MARK: - Active Session Detection

    func activeSession() -> CardioSession? {
        let inProgressRaw = SessionStatus.inProgress.rawValue
        let pausedRaw = SessionStatus.paused.rawValue

        let descriptor = FetchDescriptor<CardioSession>(
            predicate: #Predicate {
                $0.statusRaw == inProgressRaw || $0.statusRaw == pausedRaw
            },
            sortBy: [SortDescriptor(\CardioSession.startedAt, order: .reverse)]
        )

        return try? modelContext?.fetch(descriptor).first
    }

    // MARK: - Computed Metrics

    /// Current pace in seconds per kilometer (derived from distance + time).
    var currentPaceSecsPerKm: Double? {
        guard totalDistanceMeters > 100 else { return nil } // Need some distance for meaningful pace
        // This is a rough average pace; real apps use rolling windows
        return 0 // Will be computed by the view from elapsed time + distance
    }

    /// Format distance from meters to display (km with 2 decimals).
    var distanceKm: Double { totalDistanceMeters / 1000.0 }

    // MARK: - GPS Distance Tracking

    private func startGPSTracking() {
        trackingDistance = true
        lastLocation = nil
        totalDistanceMeters = 0

        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }

        locationManager.startUpdatingLocation()
    }

    private func stopGPSTracking() {
        trackingDistance = false
        locationManager.stopUpdatingLocation()
        lastLocation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard trackingDistance else { return }

        for location in locations {
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 20 else { continue }

            if let last = lastLocation {
                let delta = location.distance(from: last)
                if delta > 1.0 {
                    totalDistanceMeters += delta
                }
            }
            lastLocation = location
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[Cardio] GPS error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if (manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways), trackingDistance {
            manager.startUpdatingLocation()
        }
    }

    // MARK: - HealthKit Integration

    private func startHealthKitTracking(startDate: Date) async {

        // 2. HealthKit workout builder — fire-and-forget, don't block queries
        //    (user may have denied HK write, which causes beginCollection to hang)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try await self.hkService.requestWorkoutAuthorization()
                        let builder = self.hkService.createWorkoutBuilder(activityType: self.hkActivityType)
                        try await self.hkService.beginWorkoutBuilder(builder)
                        await MainActor.run { self.workoutBuilder = builder }
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(10))
                        throw CancellationError()
                    }
                    // First to finish wins — either setup succeeds or timeout
                    try await group.next()
                    group.cancelAll()
                }
                print("[Cardio] HK workout builder ready")
            } catch {
                print("[Cardio] HK workout builder skipped: \(error.localizedDescription)")
                await MainActor.run { self.workoutBuilder = nil }
            }
        }

        // 3. Live HR query (Watch only)
        await MainActor.run {
            hrQuery = hkService.startHeartRateQuery(from: startDate) { [weak self] bpm in
                self?.currentHeartRate = bpm
            }
        }

        // HK distance query (Watch GPS — supplements GPS tracking)
        await MainActor.run {
            let distType = HealthKitService.distanceType(for: hkActivityType)
            distanceQuery = hkService.startDistanceQuery(type: distType, from: startDate) { [weak self] addedMeters in
                guard let self, addedMeters > 0 else { return }
                // When Watch provides distance, use it (more accurate than phone GPS)
                if self.trackingDistance {
                    self.stopGPSTracking()
                }
                self.totalDistanceMeters += addedMeters
            }
        }
    }

    private func finishHealthKitTracking(session: CardioSession) async {
        stopHealthKitQueries()

        guard let builder = workoutBuilder else { return }
        workoutBuilder = nil // Clear immediately to prevent double-finish
        do {
            try await builder.endCollection(at: Date())
            let workout = try await builder.finishWorkout()
            session.hkWorkoutID = workout?.uuid.uuidString
        } catch {
            print("[Cardio] HK workout finish failed (expected if auth denied): \(error.localizedDescription)")
        }
    }

    private func stopHealthKitQueries() {
        if let q = hrQuery { hkService.stopQuery(q); hrQuery = nil }
        if let q = distanceQuery { hkService.stopQuery(q); distanceQuery = nil }
        stopGPSTracking()
    }

    // MARK: - Session Log Creation

    private func createSessionLog(for session: CardioSession, exercise: Exercise?) -> CardioSessionLog {
        let log = CardioSessionLog(exerciseID: exercise?.id)
        log.durationSeconds = Int(session.activeDuration)
        log.distance = totalDistanceMeters > 0 ? totalDistanceMeters / 1000.0 : nil
        log.calories = estimatedCalories > 0 ? estimatedCalories : nil
        log.avgHeartRate = currentHeartRate > 0 ? Int(currentHeartRate) : nil

        // Compute average pace (sec/km)
        if let dist = log.distance, dist > 0.1, log.durationSeconds > 0 {
            log.avgPace = Double(log.durationSeconds) / dist
        }

        return log
    }

    // MARK: - Auto-Completion Bridge

    private func autoCompleteShell(for session: CardioSession, cardioPlanExercise: CardioPlanExercise?) {
        guard let shellActivity = findShellActivity(for: session) else { return }

        let today = Date().startOfDay
        let shellID = shellActivity.id

        // Check if already logged today
        let existingDescriptor = FetchDescriptor<ActivityLog>(
            predicate: #Predicate { $0.activity?.id == shellID }
        )
        if let existing = try? modelContext?.fetch(existingDescriptor),
           existing.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
            return
        }

        let ratio = completionRatio(for: session, target: cardioPlanExercise)

        if ratio >= 0.8 {
            let log = ActivityLog(activity: shellActivity, date: today, status: .completed)
            modelContext?.insert(log)
        } else {
            let log = ActivityLog(activity: shellActivity, date: today, status: .skipped)
            log.skipReason = String(format: "Incomplete: %.0f%% of target", ratio * 100)
            modelContext?.insert(log)
        }
    }

    /// Completion ratio comparing actual vs target distance or duration.
    func completionRatio(for session: CardioSession, target: CardioPlanExercise?) -> Double {
        guard let target = target else { return 1.0 }

        if let targetDist = target.targetDistance, targetDist > 0 {
            let actualKm = totalDistanceMeters / 1000.0
            return actualKm / targetDist
        } else if let targetMin = target.targetDurationMin, targetMin > 0 {
            let actualMin = session.activeDuration / 60.0
            return actualMin / Double(targetMin)
        }

        return 1.0 // No target set → always complete
    }

    private func findShellActivity(for session: CardioSession) -> Activity? {
        let shellName = "\(session.planName) – \(session.dayLabel)"
        let descriptor = FetchDescriptor<Activity>(
            predicate: #Predicate { $0.name == shellName && $0.isManagedByWorkout == true }
        )
        return try? modelContext?.fetch(descriptor).first
    }
}
