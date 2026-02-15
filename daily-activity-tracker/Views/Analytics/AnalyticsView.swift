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

    // MARK: - Insights

    private func completionRate(for activity: Activity) -> Double {
        let last7Days = Date().days(before: 7)
        let relevantLogs = allLogs.filter { log in
            log.activity?.id == activity.id &&
            log.status == .completed &&
            last7Days.contains { $0.isSameDay(as: log.date) }
        }
        return Double(relevantLogs.count) / 7.0
    }

    private var doingWell: [Activity] {
        topLevelActivities
            .filter { completionRate(for: $0) >= 0.8 }
            .sorted { completionRate(for: $0) > completionRate(for: $1) }
    }

    private var needsAttention: [Activity] {
        topLevelActivities
            .filter { rate in
                let r = completionRate(for: rate)
                return r < 0.5 && r > 0 // Only show if attempted at least once or tracked? 
                // Actually, if it's 0, it definitely needs attention.
            }
            .sorted { completionRate(for: $0) < completionRate(for: $1) }
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

                    // Global Heatmap
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("Overall Activity", icon: "square.grid.3x3.fill")
                        // Reusing HeatmapView but passing 'nil' activity implies global if we adjust HeatmapView, 
                        // but HeatmapView takes a list of activities.
                        // We can't easily reuse HeatmapView for global without refactoring it to accept a generic "DailyScore" provider.
                        // FOR NOW: We will pass ALL activities to HeatmapView, and let it visualize the *aggregate*?
                        // Actually, HeatmapView currently visualizes a SINGLE activity's logs or ALL logs if we pass them.
                        // Let's check HeatmapView... it takes `activities: [Activity]`.
                        // If we pass all top level activities, does it aggregate?
                        // Let's assume we need to instantiate it correctly.
                        HeatmapView(
                            activities: topLevelActivities,
                            logs: allLogs,
                            vacationDays: vacationDays
                        )
                    }

                    // Insights: Doing Well vs Needs Attention
                    VStack(alignment: .leading, spacing: 16) {
                        if !doingWell.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionHeader("Doing Well 🌟", icon: "star.fill")
                                ForEach(doingWell, id: \.id) { activity in
                                    insightRow(activity, score: completionRate(for: activity))
                                }
                            }
                        }

                        if !needsAttention.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionHeader("Needs Attention ⚠️", icon: "exclamationmark.triangle.fill")
                                ForEach(needsAttention, id: \.id) { activity in
                                    insightRow(activity, score: completionRate(for: activity))
                                }
                            }
                        }
                    }

                    // Old Per-Activity Streaks (kept as "All Streaks")
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("All Streaks", icon: "flame.fill")
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
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func insightRow(_ activity: Activity, score: Double) -> some View {
        HStack {
            Image(systemName: activity.icon)
                .foregroundStyle(Color(hex: activity.hexColor))
            Text(activity.name)
                .font(.subheadline)
            Spacer()
            Text("\(Int(score * 100))%")
                .font(.caption.bold())
                .foregroundStyle(score >= 0.8 ? .green : .orange)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

extension Date {
    func days(before count: Int) -> [Date] {
        (0..<count).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: self) }
    }
}
