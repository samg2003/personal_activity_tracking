import SwiftUI
import SwiftData
import SQLite3

@main
struct daily_activity_trackerApp: App {

    /// Repair corrupted SwiftData store BEFORE ModelContainer opens it.
    /// Fixes orphaned GoalActivity rows referencing deleted Activities (causes
    /// "backing data could no longer be found" fatal error).
    private static func repairStoreIfNeeded() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let storeURL = appSupport.appending(path: "default.store")
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        var db: OpaquePointer?
        guard sqlite3_open(storeURL.path, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }

        // Remove GoalActivity rows whose Activity was deleted
        sqlite3_exec(db,
            "DELETE FROM ZGOALACTIVITY WHERE ZACTIVITY IS NOT NULL AND ZACTIVITY NOT IN (SELECT Z_PK FROM ZACTIVITY)",
            nil, nil, nil)

        // Backfill NULL createdAt (seconds since 2001-01-01 reference date; 0 = Jan 1 2001)
        sqlite3_exec(db, "UPDATE ZACTIVITY SET ZCREATEDAT = 0 WHERE ZCREATEDAT IS NULL", nil, nil, nil)
        sqlite3_exec(db, "UPDATE ZGOAL SET ZCREATEDAT = 0 WHERE ZCREATEDAT IS NULL", nil, nil, nil)

        // Backfill carryForward for existing metric activities (preserves behavior after ADR-16 generalization)
        sqlite3_exec(db, "UPDATE ZACTIVITY SET ZCARRYFORWARD = 1 WHERE ZTYPERAW = 'metric' AND (ZCARRYFORWARD IS NULL OR ZCARRYFORWARD = 0)", nil, nil, nil)
    }
    var sharedModelContainer: ModelContainer = {
        // Fix corrupted data BEFORE SwiftData opens the store
        repairStoreIfNeeded()

        let schema = Schema([
            Category.self,
            Activity.self,
            ActivityLog.self,
            ActivityConfigSnapshot.self,
            VacationDay.self,
            Goal.self,
            GoalActivity.self,
            // Workout domain
            MuscleGroup.self,
            Exercise.self,
            ExerciseMuscle.self,
            WorkoutPlan.self,
            WorkoutPlanDay.self,
            StrengthPlanExercise.self,
            CardioPlanExercise.self,
            StrengthSession.self,
            WorkoutSetLog.self,
            CardioSession.self,
            CardioSessionLog.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onAppear {
                    seedCategoriesIfNeeded()
                    ExerciseSeeder.seedIfNeeded(context: sharedModelContainer.mainContext)
                    setupNotifications()
                }
        }
        .modelContainer(sharedModelContainer)
    }

    /// Seed default categories on first launch
    private func seedCategoriesIfNeeded() {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<Category>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        for (i, cat) in Category.defaults.enumerated() {
            let category = Category(name: cat.name, icon: cat.icon, hexColor: cat.color, sortOrder: i)
            context.insert(category)
        }
        try? context.save()
    }

    private func setupNotifications() {
        NotificationService.shared.requestAuthorization()
        UNUserNotificationCenter.current().delegate = NotificationService.shared
    }
}
