import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab = 0
    /// Tabs that have been visited at least once — once in here, their view stays alive
    @State private var activatedTabs: Set<Int> = [0]

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
            // Dashboard is always loaded (primary tab)
            DashboardView(switchToTab: $selectedTab)
                .tabItem {
                    Label("Today", systemImage: selectedTab == 0 ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .tag(0)

            lazyTab(tag: 1) { ActivitiesListView() }
                .tabItem {
                    Label("Activities", systemImage: selectedTab == 1 ? "list.bullet.rectangle.fill" : "list.bullet")
                }
                .tag(1)

            lazyTab(tag: 2) { GoalsView() }
                .tabItem {
                    Label("Goals", systemImage: "target")
                }
                .tag(2)

            lazyTab(tag: 3) { WorkoutTabView() }
                .tabItem {
                    Label("Workouts", systemImage: "dumbbell.fill")
                }
                .tag(3)

            lazyTab(tag: 4) { AnalyticsView() }
                .tabItem {
                    Label("Analytics", systemImage: selectedTab == 4 ? "chart.bar.fill" : "chart.bar")
                }
                .tag(4)
        }
        .tint(Color(hex: 0x10B981))
        .onChange(of: selectedTab) { _, newTab in
            activatedTabs.insert(newTab)
        }
    }

    /// Instantiate tab content on first visit; keep it alive for instant re-visits.
    @ViewBuilder
    private func lazyTab<Content: View>(tag: Int, @ViewBuilder content: @escaping () -> Content) -> some View {
        if activatedTabs.contains(tag) {
            content()
        } else {
            Color(.systemGroupedBackground)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Category.self, Activity.self, ActivityLog.self, VacationDay.self, Goal.self, GoalActivity.self], inMemory: true)
        .preferredColorScheme(.dark)
}
