import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(switchToTab: $selectedTab)
                .tabItem {
                    Label("Today", systemImage: "checkmark.circle")
                }
                .tag(0)

            ActivitiesListView()
                .tabItem {
                    Label("Activities", systemImage: "list.bullet")
                }
                .tag(1)

            GoalsView()
                .tabItem {
                    Label("Goals", systemImage: "target")
                }
                .tag(2)

            WorkoutTabView()
                .tabItem {
                    Label("Workouts", systemImage: "dumbbell.fill")
                }
                .tag(3)

            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar")
                }
                .tag(4)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Category.self, Activity.self, ActivityLog.self, VacationDay.self, Goal.self, GoalActivity.self], inMemory: true)
        .preferredColorScheme(.dark)
}
