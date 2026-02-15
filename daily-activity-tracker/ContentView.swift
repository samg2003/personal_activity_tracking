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

            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar")
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Category.self, Activity.self, ActivityLog.self, VacationDay.self], inMemory: true)
        .preferredColorScheme(.dark)
}
