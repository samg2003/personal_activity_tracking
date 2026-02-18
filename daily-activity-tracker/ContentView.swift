import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Today", systemImage: "checkmark.circle")
                }

            ActivitiesListView()
                .tabItem {
                    Label("Activities", systemImage: "list.bullet")
                }

            GoalsView()
                .tabItem {
                    Label("Goals", systemImage: "target")
                }

            WorkoutTabView()
                .tabItem {
                    Label("Workouts", systemImage: "dumbbell.fill")
                }

            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar")
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Category.self, Activity.self, ActivityLog.self, VacationDay.self, Goal.self, GoalActivity.self], inMemory: true)
        .preferredColorScheme(.dark)
}
