import SwiftUI
import SwiftData

struct AnalyticsView: View {
    @Query(sort: \Activity.sortOrder) private var allActivities: [Activity]
    @Query(sort: \ActivityLog.date, order: .reverse) private var allLogs: [ActivityLog]
    @Query private var vacationDays: [VacationDay]

    private var topLevelActivities: [Activity] {
        allActivities.filter { $0.parent == nil && !$0.isArchived }
    }

    private var valueActivities: [Activity] {
        allActivities.filter { ($0.type == .value || $0.type == .cumulative) && !$0.isArchived }
    }

    // MARK: - Streak computation

    private func streakFor(_ activity: Activity) -> Int {
        let completedDates = Set(
            allLogs
                .filter { $0.activity?.id == activity.id && $0.status == .completed }
                .map { $0.date.startOfDay }
        )
        var streak = 0
        var day = Date().startOfDay
        while completedDates.contains(day) {
            streak += 1
            guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    private var topStreak: (name: String, count: Int)? {
        let streaks = topLevelActivities.map { (name: $0.name, count: streakFor($0)) }
        return streaks.max(by: { $0.count < $1.count })
    }

    /// Overall 7-day average completion score
    private var overallScore: Double {
        let calendar = Calendar.current
        let today = Date().startOfDay
        var totalScore = 0.0
        var countedDays = 0

        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if vacationDays.contains(where: { $0.date.isSameDay(as: date) }) { continue }
            let dayLogs = allLogs.filter { $0.date.isSameDay(as: date) }
            let completedCount = topLevelActivities.filter { activity in
                dayLogs.contains { $0.activity?.id == activity.id && $0.status == .completed }
            }.count
            guard !topLevelActivities.isEmpty else { continue }
            totalScore += Double(completedCount) / Double(topLevelActivities.count)
            countedDays += 1
        }
        return countedDays > 0 ? totalScore / Double(countedDays) : 0
    }

    // MARK: - Category Scorecards

    private var categoryScores: [(name: String, color: String, score: Double)] {
        let grouped = Dictionary(grouping: topLevelActivities) { $0.category?.name ?? "Uncategorized" }
        return grouped.compactMap { (catName, activities) in
            let color = activities.first?.category?.hexColor ?? "#999999"
            let total = activities.count
            guard total > 0 else { return nil }
            let todayLogs = allLogs.filter { $0.date.isSameDay(as: Date()) }
            let completed = activities.filter { activity in
                todayLogs.contains { $0.activity?.id == activity.id && $0.status == .completed }
            }.count
            return (catName, color, Double(completed) / Double(total))
        }
        .sorted { $0.score > $1.score }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    EncouragementBanner(
                        topStreak: topStreak,
                        mostImproved: nil, // Computed in future iteration
                        overallScore: overallScore
                    )

                    // Heatmap
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("Activity Heatmap", icon: "square.grid.3x3.fill")
                        HeatmapView(
                            activities: topLevelActivities,
                            logs: allLogs,
                            vacationDays: vacationDays
                        )
                    }

                    // Category Scorecards
                    if !categoryScores.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader("Categories", icon: "folder.fill")
                            ForEach(categoryScores, id: \.name) { score in
                                categoryRow(score)
                            }
                        }
                    }

                    // Per-Activity Streaks
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("Streaks", icon: "flame.fill")
                        ForEach(topLevelActivities) { activity in
                            streakRow(activity)
                        }
                    }

                    // Value Charts
                    if !valueActivities.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader("Trends", icon: "chart.line.uptrend.xyaxis")
                            ForEach(valueActivities) { activity in
                                ValueChartView(activity: activity, logs: allLogs)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemBackground))
            .navigationTitle("Analytics")
        }
    }

    // MARK: - Sub-views

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title.uppercased())
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func categoryRow(_ score: (name: String, color: String, score: Double)) -> some View {
        HStack {
            Circle()
                .fill(Color(hex: score.color))
                .frame(width: 8, height: 8)
            Text(score.name)
                .font(.subheadline)

            Spacer()

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: score.color))
                        .frame(width: geo.size.width * score.score)
                }
            }
            .frame(width: 80, height: 8)

            Text("\(Int(score.score * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func streakRow(_ activity: Activity) -> some View {
        let streak = streakFor(activity)
        return HStack {
            Image(systemName: activity.icon)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: activity.hexColor))
                .frame(width: 24)

            Text(activity.name)
                .font(.subheadline)

            Spacer()

            if streak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    Text("\(streak)d")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(.orange)
                }
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
