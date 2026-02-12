import SwiftUI
import SwiftData

@main
struct daily_activity_trackerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Category.self,
            Activity.self,
            ActivityLog.self,
            VacationDay.self,
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
                .onAppear { seedCategoriesIfNeeded() }
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
}
