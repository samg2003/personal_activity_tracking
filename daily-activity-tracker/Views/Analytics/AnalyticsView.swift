import SwiftUI
import SwiftData

struct AnalyticsView: View {
    @Query(sort: \Activity.sortOrder) private var allActivities: [Activity]
    @Query(sort: \ActivityLog.date, order: .reverse) private var allLogs: [ActivityLog]
    @Query private var vacationDays: [VacationDay]

    @State private var selectedTab: AnalyticsTab = .activities

    // Centralized analytics cache — computed ONCE, shared by all sections
    @State private var streaks: [(activity: Activity, streak: Int)] = []
    @State private var completionRates: [(activity: Activity, rate: Double)] = []
    @State private var biggestWins: [(activity: Activity, delta: String)] = []
    @State private var deepDiveGroups: [(label: String, icon: String, activities: [Activity])] = []
    @State private var cachedPhotoActivities: [Activity] = []
    @State private var analyticsReady = false

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

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
        .task {
            guard !analyticsReady else { return }
            await computeAllAnalytics()
        }
        .onChange(of: allLogs.count) {
            analyticsReady = false
            Task { await computeAllAnalytics() }
        }
    }

    // MARK: - Activities Content

    private var activitiesContent: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                // 1. Insight Summary
                if analyticsReady {
                    let bestStreak = streaks.max(by: { $0.streak < $1.streak }).map { ($0.activity.name, $0.streak) }
                    let behindCount = completionRates.filter { $0.rate < 0.5 && $0.rate > 0 }.count
                    let topWin = biggestWins.first
                    InsightSummaryCard(
                        bestStreak: bestStreak,
                        biggestWin: topWin.map { ($0.activity.name, $0.delta) },
                        behindCount: behindCount
                    )
                } else {
                    sectionPlaceholder(height: 80)
                }

                // 2. Consistency Heatmap (self-loading — different data shape)
                VStack(alignment: .leading, spacing: 8) {
                    analyticsSectionHeader("Consistency Map", icon: "square.grid.3x3.fill")
                    HeatmapView(
                        activities: topLevelActivities,
                        allActivities: allActivities,
                        logs: allLogs,
                        vacationDays: vacationDays,
                        scheduleEngine: ScheduleEngine()
                    )
                }

                // 3. Behind Schedule
                if analyticsReady {
                    let behindItems = completionRates.filter { $0.rate < 0.5 && $0.rate > 0 }.sorted { $0.rate < $1.rate }
                    if !behindItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            analyticsSectionHeader("Behind Schedule", icon: "exclamationmark.triangle.fill")
                            ForEach(behindItems, id: \.activity.id) { item in
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
                } else {
                    sectionPlaceholder(height: 60)
                }

                // 4. Streak Leaderboard
                if analyticsReady {
                    StreakLeaderboardSectionView(
                        items: streaks.sorted { $0.streak > $1.streak },
                        allLogs: allLogs,
                        allActivities: allActivities,
                        vacationDays: vacationDays
                    )
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        analyticsSectionHeader("Streak Leaderboard", icon: "flame.fill")
                        sectionPlaceholder(height: 120)
                    }
                }

                // 5. Biggest Wins
                if analyticsReady && !biggestWins.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        analyticsSectionHeader("Biggest Wins", icon: "arrow.up.right")
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
                } else if !analyticsReady {
                    sectionPlaceholder(height: 60)
                }

                // 6. Trends (Value Charts)
                if analyticsReady && !valueActivities.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        analyticsSectionHeader("Trends", icon: "chart.line.uptrend.xyaxis")
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
                if !cachedPhotoActivities.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        analyticsSectionHeader("Photo Progress", icon: "person.2.crop.square.stack")
                        ForEach(cachedPhotoActivities) { activity in
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
                if analyticsReady && !deepDiveGroups.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        analyticsSectionHeader("Deep Dive", icon: "magnifyingglass")

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
                } else if !analyticsReady {
                    VStack(alignment: .leading, spacing: 8) {
                        analyticsSectionHeader("Deep Dive", icon: "magnifyingglass")
                        sectionPlaceholder(height: 120)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Centralized Compute (ONE pass for everything)

    private func computeAllAnalytics() async {
        let engine = ScheduleEngine()
        let activities = topLevelActivities
        let values = valueActivities

        // Single log index — O(n) once
        let logIndex = engine.preIndexLogs(allLogs)
        let vacationSet = Set(vacationDays.map { $0.date.startOfDay })

        await Task.yield()

        // Batch streaks (yields per-activity internally)
        streaks = await engine.batchCurrentStreaks(
            for: activities, logIndex: logIndex,
            allActivities: allActivities, vacationSet: vacationSet
        )

        await Task.yield()

        // Batch completion rates (yields per-activity internally)
        completionRates = await engine.batchCompletionRates(
            for: activities, days: 7, logIndex: logIndex,
            vacationSet: vacationSet, allActivities: allActivities
        )

        await Task.yield()

        // Lightweight computations
        biggestWins = Self.buildBiggestWins(values: values, logIndex: logIndex)
        deepDiveGroups = Self.buildDeepDiveGroups(allActivities: allActivities, logIndex: logIndex)

        cachedPhotoActivities = allActivities.filter {
            $0.type == .metric && $0.metricKind == .photo
            && !MediaService.shared.allPhotos(for: $0.id).isEmpty
        }

        analyticsReady = true
    }

    private static func buildBiggestWins(values: [Activity], logIndex: [UUID: [ActivityLog]]) -> [(Activity, String)] {
        let calendar = Calendar.current
        let now = Date().startOfDay
        guard let s1 = calendar.date(byAdding: .day, value: -6, to: now),
              let s2 = calendar.date(byAdding: .day, value: -13, to: now),
              let e2 = calendar.date(byAdding: .day, value: -7, to: now)
        else { return [] }

        var results: [(activity: Activity, delta: Double, formatted: String)] = []
        for activity in values {
            let logs = logIndex[activity.id] ?? []
            let tw = logs.filter { $0.status == .completed && $0.value != nil && $0.date >= s1 && $0.date <= now }
            let lw = logs.filter { $0.status == .completed && $0.value != nil && $0.date >= s2 && $0.date <= e2 }
            guard !tw.isEmpty, !lw.isEmpty else { continue }
            let ta = activity.type == .cumulative ? activity.aggregateMultiDayValue(from: tw)
                : tw.compactMap(\.value).reduce(0, +) / Double(tw.count)
            let la = activity.type == .cumulative ? activity.aggregateMultiDayValue(from: lw)
                : lw.compactMap(\.value).reduce(0, +) / Double(lw.count)
            let d = ta - la
            guard abs(d) > 0.01 else { continue }
            let unit = activity.unit ?? ""
            let sign = d > 0 ? "+" : ""
            let f = abs(d) >= 10 ? "\(sign)\(Int(d))\(unit)/wk" : "\(sign)\(String(format: "%.1f", d))\(unit)/wk"
            results.append((activity, abs(d), f))
        }
        return results.sorted { $0.1 > $1.1 }.prefix(3).map { ($0.0, $0.2) }
    }

    private static func buildDeepDiveGroups(allActivities: [Activity], logIndex: [UUID: [ActivityLog]]) -> [(String, String, [Activity])] {
        let eligible = allActivities.filter {
            $0.parent == nil && $0.type != .container
            && $0.schedule.type != .sticky && $0.schedule.type != .adhoc
        }
        let sortedByRecency: (Activity, Activity) -> Bool = { a, b in
            let aDate = logIndex[a.id]?.first?.date ?? .distantPast
            let bDate = logIndex[b.id]?.first?.date ?? .distantPast
            return aDate > bDate
        }
        var g: [(label: String, icon: String, activities: [Activity])] = []
        let checkboxes = eligible.filter { $0.type == .checkbox }.sorted(by: sortedByRecency)
        if !checkboxes.isEmpty { g.append(("Checkbox", "checkmark.circle", checkboxes)) }
        let values = eligible.filter { $0.type == .value }.sorted(by: sortedByRecency)
        if !values.isEmpty { g.append(("Value", "number", values)) }
        let cumulatives = eligible.filter { $0.type == .cumulative }.sorted(by: sortedByRecency)
        if !cumulatives.isEmpty { g.append(("Cumulative", "chart.bar.fill", cumulatives)) }
        let metrics = eligible.filter { $0.type == .metric }.sorted(by: sortedByRecency)
        if !metrics.isEmpty { g.append(("Metric", "chart.line.uptrend.xyaxis", metrics)) }
        return g
    }
}

// MARK: - Streak Leaderboard (pure renderer, data pre-computed)

private struct StreakLeaderboardSectionView: View {
    let items: [(activity: Activity, streak: Int)]
    let allLogs: [ActivityLog]
    let allActivities: [Activity]
    let vacationDays: [VacationDay]

    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            analyticsSectionHeader("Streak Leaderboard", icon: "flame.fill")

            let visible = showAll ? items : Array(items.prefix(5))
            ForEach(visible, id: \.activity.id) { item in
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

            if items.count > 5 {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showAll.toggle() }
                } label: {
                    Text(showAll ? "Show Less" : "Show All (\(items.count))")
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
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

                Image(systemName: "flame.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(streak > 0 ? .orange : Color.gray.opacity(0.3))

                Text("\(streak)d")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(streak > 0 ? Color.orange : Color.gray.opacity(0.5)))
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

// MARK: - Shared Row Views

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

// MARK: - Shared Placeholder

private func sectionPlaceholder(height: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: WDS.cardRadius, style: .continuous)
        .fill(.ultraThinMaterial)
        .frame(height: height)
        .overlay {
            ProgressView()
                .tint(.secondary)
        }
}

private func analyticsSectionHeader(_ title: String, icon: String, color: Color = Color(hex: 0x10B981)) -> some View {
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

extension Date {
    func days(before count: Int) -> [Date] {
        (0..<count).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: self) }
    }
}
