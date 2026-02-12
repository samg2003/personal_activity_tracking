import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Today", systemImage: "checkmark.circle")
                }

            // Placeholder for future Analytics tab
            Text("Analytics Coming Soon")
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
