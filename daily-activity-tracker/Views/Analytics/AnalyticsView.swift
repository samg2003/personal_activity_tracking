import SwiftUI
import SwiftData

struct AnalyticsView: View {
    @Query(sort: \Activity.sortOrder) private var allActivities: [Activity]
    @Query(sort: \ActivityLog.date, order: .reverse) private var allLogs: [ActivityLog]
    @Query private var vacationDays: [VacationDay]

    private let scheduleEngine = ScheduleEngine()

    @State private var showAllStreaks = false
    @State private var selectedTab: AnalyticsTab = .activities

    enum AnalyticsTab: String, CaseIterable {
        case activities = "Activities"
        case workouts = "Workouts"
    }

    private var topLevelActivities: [Activity] {
        allActivities.filter {
            $0.parent == nil && !$0.isStopped
            && $0.schedule.type != .sticky && $0.schedule.type != .adhoc
        }
    }

    private var valueActivities: [Activity] {
        allActivities.filter {
            !$0.isStopped && ($0.type == .value || $0.type == .cumulative)
            && $0.schedule.type != .sticky && $0.schedule.type != .adhoc
        }
    }

    private var photoActivities: [Activity] {
        allActivities.filter {
            $0.type == .metric && $0.metricKind == .photo
            && !MediaService.shared.allPhotos(for: $0.id).isEmpty
        }
    }

    // MARK: - Deep Dive Groups

    private var deepDiveGroups: [(label: String, icon: String, activities: [Activity])] {
        let eligible = allActivities.filter {
            $0.parent == nil
            && $0.type != .container
            && $0.schedule.type != .sticky && $0.schedule.type != .adhoc
        }

        // Sort by recency of last log (most recent first)
        let sortedByRecency: (Activity, Activity) -> Bool = { a, b in
            let aDate = allLogs.first(where: { $0.activity?.id == a.id })?.date ?? .distantPast
            let bDate = allLogs.first(where: { $0.activity?.id == b.id })?.date ?? .distantPast
            return aDate > bDate
        }

        var groups: [(label: String, icon: String, activities: [Activity])] = []

        let checkboxes = eligible.filter { $0.type == .checkbox }.sorted(by: sortedByRecency)
        if !checkboxes.isEmpty { groups.append(("Checkbox", "checkmark.circle", checkboxes)) }

        let values = eligible.filter { $0.type == .value }.sorted(by: sortedByRecency)
        if !values.isEmpty { groups.append(("Value", "number", values)) }

        let cumulatives = eligible.filter { $0.type == .cumulative }.sorted(by: sortedByRecency)
        if !cumulatives.isEmpty { groups.append(("Cumulative", "chart.bar.fill", cumulatives)) }

        let metrics = eligible.filter { $0.type == .metric }.sorted(by: sortedByRecency)
        if !metrics.isEmpty { groups.append(("Metric", "chart.line.uptrend.xyaxis", metrics)) }

        return groups
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
            VStack(spacing: 0) {
                // Segmented control
                Picker("", selection: $selectedTab) {
                    ForEach(AnalyticsTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                switch selectedTab {
                case .activities:
                    activitiesContent
                case .workouts:
                    WorkoutAnalyticsView()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Analytics")
        }
    }

    // MARK: - Activities Content

    private var activitiesContent: some View {
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

                // 7. Photo Progress
                if !photoActivities.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("Photo Progress", icon: "person.2.crop.square.stack")
                        ForEach(photoActivities) { activity in
                            NavigationLink {
                                ActivityAnalyticsView(
                                    activity: activity,
                                    allLogs: allLogs,
                                    vacationDays: vacationDays,
                                    allActivities: allActivities
                                )
                            } label: {
                                PhotoComparisonCard(activity: activity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // 8. Deep Dive
                if !deepDiveGroups.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("Deep Dive", icon: "magnifyingglass")

                        ForEach(deepDiveGroups, id: \.label) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: group.icon)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    Text(group.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 4)

                                ForEach(group.activities) { activity in
                                    NavigationLink {
                                        ActivityAnalyticsView(
                                            activity: activity,
                                            allLogs: allLogs,
                                            vacationDays: vacationDays,
                                            allActivities: allActivities
                                        )
                                    } label: {
                                        deepDiveRow(activity)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Sub-views

    private func sectionHeader(_ title: String, icon: String, color: Color = Color(hex: 0x10B981)) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(color))

            Text(title.uppercased())
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func streakRow(_ activity: Activity, streak: Int) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: activity.hexColor))
                .frame(width: 4)
                .padding(.vertical, 6)

            HStack(spacing: 10) {
                Image(systemName: activity.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: activity.hexColor))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color(hex: activity.hexColor).opacity(0.12)))

                Text(activity.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Spacer()

                if streak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                        Text("\(streak)d")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.orange))
                    }
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
        }
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: WDS.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    private func behindRow(_ activity: Activity, rate: Double) -> some View {
        let barColor: Color = rate < 0.25 ? .red : .orange
        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(barColor)
                .frame(width: 4)
                .padding(.vertical, 6)

            HStack(spacing: 10) {
                Image(systemName: activity.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: activity.hexColor))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color(hex: activity.hexColor).opacity(0.12)))

                Text(activity.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Spacer()

                // Gradient mini progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [barColor.opacity(0.5), barColor],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * rate)
                    }
                }
                .frame(width: 60, height: 8)

                Text("\(Int(rate * 100))%")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(barColor))
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: WDS.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    private func winRow(_ activity: Activity, delta: String) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.green)
                .frame(width: 4)
                .padding(.vertical, 6)

            HStack(spacing: 10) {
                Image(systemName: activity.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: activity.hexColor))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color(hex: activity.hexColor).opacity(0.12)))

                Text(activity.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Spacer()

                Text(delta)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.green))
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: WDS.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    private func deepDiveRow(_ activity: Activity) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: activity.hexColor))
                .frame(width: 4)
                .padding(.vertical, 6)

            HStack(spacing: 10) {
                Image(systemName: activity.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: activity.hexColor))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color(hex: activity.hexColor).opacity(0.12)))

                Text(activity.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                if activity.isStopped {
                    Text("Paused")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                // Last logged date
                if let lastLog = allLogs.first(where: { $0.activity?.id == activity.id }) {
                    Text(lastLog.date, format: .dateTime.month(.abbreviated).day().year())
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: WDS.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}

extension Date {
    func days(before count: Int) -> [Date] {
        (0..<count).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: self) }
    }
}
