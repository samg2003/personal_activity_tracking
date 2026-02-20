import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab = 0

    init() {
        // Premium tab bar appearance
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(switchToTab: $selectedTab)
                .tabItem {
                    Label("Today", systemImage: selectedTab == 0 ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .tag(0)

            ActivitiesListView()
                .tabItem {
                    Label("Activities", systemImage: selectedTab == 1 ? "list.bullet.rectangle.fill" : "list.bullet")
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
                    Label("Analytics", systemImage: selectedTab == 4 ? "chart.bar.fill" : "chart.bar")
                }
                .tag(4)
        }
        .tint(Color(hex: 0x10B981))
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Category.self, Activity.self, ActivityLog.self, VacationDay.self, Goal.self, GoalActivity.self], inMemory: true)
        .preferredColorScheme(.dark)
}
