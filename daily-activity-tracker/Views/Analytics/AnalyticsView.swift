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

    // MARK: - Optimization Caches
    
    private var logsByActivity: [UUID: [ActivityLog]] {
        Dictionary(grouping: allLogs) { $0.activity?.id ?? UUID() }
    }

    // MARK: - Streak computation

    private func streakFor(_ activity: Activity) -> Int {
        let logs = logsByActivity[activity.id] ?? []
        let completedDates = Set(
            logs
                .filter { $0.status == .completed }
                .map { $0.date.startOfDay }
        )
        
        var streak = 0
        var day = Date().startOfDay
        // Check today or yesterday to start streak (allow for today not done yet)
        if !completedDates.contains(day) {
            guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = prev
        }
        
        // Loop backwards in time
        // Safety limit: 3650 days (10 years) to avoid infinite loops if glitches occur
        for _ in 0..<3650 {
            if completedDates.contains(day) {
                streak += 1
            } else if vacationDays.contains(where: { $0.date.isSameDay(as: day) }) {
                 // Vacation: maintain streak, don't increment, don't break
            } else {
                break
            }
            
            guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }

        return streak
    }

    private var topStreak: (name: String, count: Int)? {
        let streaks = topLevelActivities.map { (name: $0.name, count: streakFor($0)) }
        return streaks.max(by: { $0.count < $1.count })
    }
    
    // MARK: - Most Improved
    
    private var mostImproved: (name: String, delta: Double)? {
        let now = Date().startOfDay
        let calendar = Calendar.current
        
        guard let startOfThisWeek = calendar.date(byAdding: .day, value: -6, to: now),
              let startOfLastWeek = calendar.date(byAdding: .day, value: -13, to: now),
              let endOfLastWeek = calendar.date(byAdding: .day, value: -7, to: now)
        else { return nil }
        
        // Pre-compute vacation date set for fast lookup
        let vacationDateSet = Set(vacationDays.map { $0.date.startOfDay })
        
        // Count non-vacation days in each period for normalization
        let thisWeekDays = (0...6).filter { offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: now) else { return false }
            return !vacationDateSet.contains(d)
        }.count
        let lastWeekDays = (7...13).filter { offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: now) else { return false }
            return !vacationDateSet.contains(d)
        }.count
        
        guard thisWeekDays > 0, lastWeekDays > 0 else { return nil }
        
        var bestDelta = 0.0
        var bestActivity: Activity?
        
        for activity in topLevelActivities {
            let logs = logsByActivity[activity.id] ?? []
            
            let thisWeekCount = logs.filter {
                $0.status == .completed &&
                $0.date >= startOfThisWeek && $0.date <= now &&
                !vacationDateSet.contains($0.date.startOfDay)
            }.count
            
            let lastWeekCount = logs.filter {
                $0.status == .completed &&
                $0.date >= startOfLastWeek && $0.date <= endOfLastWeek &&
                !vacationDateSet.contains($0.date.startOfDay)
            }.count
            
            // Normalize: rate this week vs rate last week
            let thisRate = Double(thisWeekCount) / Double(thisWeekDays)
            let lastRate = Double(lastWeekCount) / Double(lastWeekDays)
            let delta = thisRate - lastRate
            
            if delta > bestDelta {
                bestDelta = delta
                bestActivity = activity
            }
        }
        
        if let best = bestActivity, bestDelta > 0 {
            return (best.name, bestDelta)
        }
        return nil
    }

    /// Overall 7-day average completion score
    private var overallScore: Double {
        let calendar = Calendar.current
        let today = Date().startOfDay
        var totalScore = 0.0
        var countedDays = 0
        
        // Improve: Use pre-grouped logs
        // Group logs by Date (StartOfDay)
        let logsByDate = Dictionary(grouping: allLogs) { $0.date.startOfDay }

        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if vacationDays.contains(where: { $0.date.isSameDay(as: date) }) { continue }
            
            let dayLogs = logsByDate[date] ?? []
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
    
    // Kept simple, relies on filtered logsByActivity implicitly for optimization if rewritten
    // But since it's just categories, the current implementation filters `allLogs` for Today only.
    // That's O(M) where M is logs. Acceptable.

    // MARK: - Insights

    private func completionRate(for activity: Activity) -> Double {
        let logs = logsByActivity[activity.id] ?? []
        let calendar = Calendar.current
        let today = Date().startOfDay
        let vacationDateSet = Set(vacationDays.map { $0.date.startOfDay })
        
        // Count non-vacation days in last 7
        let eligibleDays = (0..<7).filter { offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: today) else { return false }
            return !vacationDateSet.contains(d)
        }.count
        
        guard eligibleDays > 0 else { return 0 }
        
        let cutoff = calendar.date(byAdding: .day, value: -7, to: today)!
        let relevantCount = logs.filter {
            $0.status == .completed && $0.date > cutoff &&
            !vacationDateSet.contains($0.date.startOfDay)
        }.count
        return Double(relevantCount) / Double(eligibleDays)
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
                return r < 0.5 && r > 0
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
                        mostImproved: mostImproved?.name,
                        overallScore: overallScore
                    )

                    // Global Heatmap
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("Overall Activity", icon: "square.grid.3x3.fill")
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

}

extension Date {
    func days(before count: Int) -> [Date] {
        (0..<count).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: self) }
    }
}
