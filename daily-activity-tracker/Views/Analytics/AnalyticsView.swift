import SwiftUI
import SwiftData

struct AnalyticsView: View {
    @Query(sort: \Activity.sortOrder) private var allActivities: [Activity]
    @Query(sort: \ActivityLog.date, order: .reverse) private var allLogs: [ActivityLog]
    @Query private var vacationDays: [VacationDay]

    private let scheduleEngine = ScheduleEngine()

    @State private var showAllStreaks = false

    private var topLevelActivities: [Activity] {
        allActivities.filter { $0.parent == nil && !$0.isStopped }
    }

    private var valueActivities: [Activity] {
        allActivities.filter {
            !$0.isStopped && ($0.type == .value || $0.type == .cumulative)
        }
    }

    // MARK: - Streak Leaderboard

    private var sortedStreaks: [(activity: Activity, streak: Int)] {
        topLevelActivities
            .map { (activity: $0, streak: scheduleEngine.currentStreak(for: $0, logs: allLogs, allActivities: allActivities, vacationDays: vacationDays)) }
            .sorted { $0.streak > $1.streak }
    }

    private var bestStreak: (name: String, count: Int)? {
        sortedStreaks.first.map { ($0.activity.name, $0.streak) }
    }

    // MARK: - Behind Schedule

    private var behindSchedule: [(activity: Activity, rate: Double)] {
        topLevelActivities
            .map { (activity: $0, rate: scheduleEngine.completionRate(for: $0, days: 7, logs: allLogs, vacationDays: vacationDays, allActivities: allActivities)) }
            .filter { $0.rate < 0.5 && $0.rate > 0 }
            .sorted { $0.rate < $1.rate }
    }

    // MARK: - Biggest Wins (metric improvements this week vs last)

    private var biggestWins: [(activity: Activity, delta: String)] {
        let calendar = Calendar.current
        let now = Date().startOfDay
        guard let startOfThisWeek = calendar.date(byAdding: .day, value: -6, to: now),
              let startOfLastWeek = calendar.date(byAdding: .day, value: -13, to: now),
              let endOfLastWeek = calendar.date(byAdding: .day, value: -7, to: now)
        else { return [] }

        var results: [(activity: Activity, delta: Double, formatted: String)] = []
        let logsByActivity = Dictionary(grouping: allLogs) { $0.activity?.id ?? UUID() }

        for activity in valueActivities {
            let logs = logsByActivity[activity.id] ?? []
            let thisWeekLogs = logs.filter {
                $0.status == .completed && $0.value != nil &&
                $0.date >= startOfThisWeek && $0.date <= now
            }
            let lastWeekLogs = logs.filter {
                $0.status == .completed && $0.value != nil &&
                $0.date >= startOfLastWeek && $0.date <= endOfLastWeek
            }

            guard !thisWeekLogs.isEmpty, !lastWeekLogs.isEmpty else { continue }

            // Use centralized aggregation for cumulative activities (groups by day first)
            let thisAvg = activity.type == .cumulative
                ? activity.aggregateMultiDayValue(from: thisWeekLogs)
                : thisWeekLogs.compactMap(\.value).reduce(0, +) / Double(thisWeekLogs.count)
            let lastAvg = activity.type == .cumulative
                ? activity.aggregateMultiDayValue(from: lastWeekLogs)
                : lastWeekLogs.compactMap(\.value).reduce(0, +) / Double(lastWeekLogs.count)

            let delta = thisAvg - lastAvg
            guard abs(delta) > 0.01 else { continue }

            let unit = activity.unit ?? ""
            let sign = delta > 0 ? "+" : ""
            let formatted: String
            if abs(delta) >= 10 {
                formatted = "\(sign)\(Int(delta))\(unit)/wk"
            } else {
                formatted = "\(sign)\(String(format: "%.1f", delta))\(unit)/wk"
            }

            results.append((activity, abs(delta), formatted))
        }

        return results
            .sorted { $0.delta > $1.delta }
            .prefix(3)
            .map { ($0.activity, $0.formatted) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 1. Insight Summary
                    InsightSummaryCard(
                        bestStreak: bestStreak,
                        biggestWin: biggestWins.first.map { ($0.activity.name, $0.delta) },
                        behindCount: behindSchedule.count
                    )

                    // 2. Consistency Map (Heatmap)
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("Consistency Map", icon: "square.grid.3x3.fill")
                        HeatmapView(
                            activities: topLevelActivities,
                            allActivities: allActivities,
                            logs: allLogs,
                            vacationDays: vacationDays,
                            scheduleEngine: ScheduleEngine()
                        )
                    }

                    // 3. Behind Schedule
                    if !behindSchedule.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader("Behind Schedule", icon: "exclamationmark.triangle.fill")
                            ForEach(behindSchedule, id: \.activity.id) { item in
                                NavigationLink {
                                    ActivityAnalyticsView(
                                        activity: item.activity,
                                        allLogs: allLogs,
                                        vacationDays: vacationDays,
                                        allActivities: allActivities
                                    )
                                } label: {
                                    behindRow(item.activity, rate: item.rate)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // 4. Streak Leaderboard
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("Streak Leaderboard", icon: "flame.fill")

                        let visibleStreaks = showAllStreaks
                            ? sortedStreaks
                            : Array(sortedStreaks.prefix(5))

                        ForEach(visibleStreaks, id: \.activity.id) { item in
                            NavigationLink {
                                ActivityAnalyticsView(
                                    activity: item.activity,
                                    allLogs: allLogs,
                                    vacationDays: vacationDays,
                                    allActivities: allActivities
                                )
                            } label: {
                                streakRow(item.activity, streak: item.streak)
                            }
                            .buttonStyle(.plain)
                        }

                        if sortedStreaks.count > 5 {
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showAllStreaks.toggle()
                                }
                            } label: {
                                Text(showAllStreaks ? "Show Less" : "Show All (\(sortedStreaks.count))")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.accentColor)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                        }
                    }

                    // 5. Biggest Wins
                    if !biggestWins.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader("Biggest Wins", icon: "arrow.up.right")
                            ForEach(biggestWins, id: \.activity.id) { item in
                                NavigationLink {
                                    ActivityAnalyticsView(
                                        activity: item.activity,
                                        allLogs: allLogs,
                                        vacationDays: vacationDays,
                                        allActivities: allActivities
                                    )
                                } label: {
                                    winRow(item.activity, delta: item.delta)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // 6. Trends (Value Charts)
                    if !valueActivities.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader("Trends", icon: "chart.line.uptrend.xyaxis")
                            ForEach(valueActivities) { activity in
                                NavigationLink {
                                    ActivityAnalyticsView(
                                        activity: activity,
                                        allLogs: allLogs,
                                        vacationDays: vacationDays,
                                        allActivities: allActivities
                                    )
                                } label: {
                                    ValueChartView(activity: activity, logs: allLogs)
                                }
                                .buttonStyle(.plain)
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

    private func streakRow(_ activity: Activity, streak: Int) -> some View {
        HStack {
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

    private func behindRow(_ activity: Activity, rate: Double) -> some View {
        HStack(spacing: 10) {
            Image(systemName: activity.icon)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: activity.hexColor))
                .frame(width: 24)

            Text(activity.name)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            // Mini progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(rate < 0.25 ? Color.red.opacity(0.7) : Color.orange.opacity(0.7))
                        .frame(width: geo.size.width * rate)
                }
            }
            .frame(width: 60, height: 6)

            Text("\(Int(rate * 100))%")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(rate < 0.25 ? .red : .orange)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func winRow(_ activity: Activity, delta: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: activity.icon)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: activity.hexColor))
                .frame(width: 24)

            Text(activity.name)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            Text(delta)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.green)
        }
        .padding(.vertical, 8)
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
