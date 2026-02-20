import SwiftUI
import SwiftData

/// Per-activity analytics detail view with Apple Health-style charts
struct ActivityAnalyticsView: View {
    let activity: Activity
    let allLogs: [ActivityLog]
    let vacationDays: [VacationDay]
    let allActivities: [Activity]

    enum TimeRange: String, CaseIterable {
        case day = "Day"
        case week = "Week"
        case month = "Month"
        case halfYear = "6M"
        case year = "1Y"
        case threeYear = "3Y"
    }

    @State private var selectedRange: TimeRange = .week
    @State private var offset: Int = 0 // 0 = current period, -1 = previous, etc.

    private let calendar = Calendar.current
    private let scheduleEngine = ScheduleEngine()

    // MARK: - Filtered logs for this activity

    private var activityLogs: [ActivityLog] {
        allLogs.filter { $0.activity?.id == activity.id }
    }

    /// Logs including children (for containers)
    private var effectiveLogs: [ActivityLog] {
        if activity.type == .container {
            // Use all children (include archived for historical accuracy)
            let childIDs = Set(activity.children.map(\.id))
            return allLogs.filter { log in
                guard let aid = log.activity?.id else { return false }
                return childIDs.contains(aid)
            }
        }
        return activityLogs
    }

    // MARK: - Streak Computation

    private var currentStreakValue: Int {
        scheduleEngine.currentStreak(for: activity, logs: allLogs, allActivities: allActivities, vacationDays: vacationDays)
    }

    private var longestStreakValue: Int {
        scheduleEngine.longestStreak(for: activity, logs: allLogs, allActivities: allActivities, vacationDays: vacationDays)
    }

    // MARK: - Chart Data

    private var chartBars: [BarChartView.BarData] {
        switch selectedRange {
        case .day: return dailyBars()
        case .week: return weeklyBars()
        case .month: return monthlyBars()
        case .halfYear: return weeklyAggregatedBars(weeks: 26)
        case .year: return weeklyAggregatedBars(weeks: 52)
        case .threeYear: return weeklyAggregatedBars(weeks: 156)
        }
    }

    private var chartDateLabel: String {
        switch selectedRange {
        case .day:
            let base = calendar.date(byAdding: .weekOfYear, value: offset, to: Date().startOfDay)!
            let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: base))!
            let end = calendar.date(byAdding: .day, value: 6, to: start)!
            return "\(start.shortDisplay) – \(end.shortDisplay)"
        case .week:
            let base = calendar.date(byAdding: .weekOfYear, value: offset, to: Date().startOfDay)!
            let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: base))!
            let end = calendar.date(byAdding: .day, value: 6, to: start)!
            return "\(start.shortDisplay) – \(end.shortDisplay)"
        case .month:
            let base = calendar.date(byAdding: .month, value: offset, to: Date().startOfDay)!
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: base)
        case .halfYear, .year, .threeYear:
            let weeks = selectedRange == .halfYear ? 26 : (selectedRange == .year ? 52 : 156)
            let end = calendar.date(byAdding: .weekOfYear, value: offset * weeks, to: Date().startOfDay)!
            let start = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: end)!
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM yyyy"
            return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
        }
    }

    /// Day mode: 7 bars (one per day of current week)
    private func dailyBars() -> [BarChartView.BarData] {
        let base = calendar.date(byAdding: .weekOfYear, value: offset, to: Date().startOfDay)!
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: base))!
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"

        return (0..<7).map { dayOffset in
            let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart)!
            let value = valueForDay(day)
            return BarChartView.BarData(
                label: dayFormatter.string(from: day),
                value: value,
                date: day
            )
        }
    }

    /// Week mode: 7 bars (one per day of selected week) — same as daily
    private func weeklyBars() -> [BarChartView.BarData] {
        dailyBars()
    }

    /// Month mode: one bar per day of the month
    private func monthlyBars() -> [BarChartView.BarData] {
        let base = calendar.date(byAdding: .month, value: offset, to: Date().startOfDay)!
        let range = calendar.range(of: .day, in: .month, for: base)!

        let comps = calendar.dateComponents([.year, .month], from: base)
        let monthStart = calendar.date(from: comps)!

        return range.map { dayNum in
            let day = calendar.date(byAdding: .day, value: dayNum - 1, to: monthStart)!
            let value = valueForDay(day)
            return BarChartView.BarData(
                label: "\(dayNum)",
                value: value,
                date: day
            )
        }
    }

    /// Wider ranges: each bar = 1 week aggregate
    private func weeklyAggregatedBars(weeks: Int) -> [BarChartView.BarData] {
        let today = Date().startOfDay
        let endAnchor = calendar.date(byAdding: .weekOfYear, value: offset * weeks, to: today)!
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"

        return (0..<weeks).reversed().map { weekOffset in
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: endAnchor)!
            let weekStart = calendar.date(byAdding: .day, value: -6, to: weekEnd)!

            let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
            let values = days.map { valueForDay($0) }

            let aggregate: Double
            switch activity.type {
            case .checkbox:
                aggregate = values.reduce(0, +) // total completions in week
            case .value, .metric, .cumulative, .container:
                // Average daily values across the period (non-zero days only)
                let nonZero = values.filter { $0 > 0 }
                aggregate = nonZero.isEmpty ? 0 : nonZero.reduce(0, +) / Double(nonZero.count)
            }

            return BarChartView.BarData(
                label: fmt.string(from: weekStart),
                value: aggregate,
                date: weekStart
            )
        }
    }

    private func valueForDay(_ day: Date) -> Double {
        switch activity.type {
        case .checkbox:
            let count = activityLogs.filter {
                $0.status == .completed && $0.date.isSameDay(as: day)
            }.count
            return Double(count)

        case .value:
            let dayValues = activityLogs
                .filter { $0.status == .completed && $0.date.isSameDay(as: day) }
                .compactMap(\.value)
            guard !dayValues.isEmpty else { return 0 }
            return dayValues.reduce(0, +) / Double(dayValues.count)

        case .cumulative:
            let values = activityLogs
                .filter { $0.status == .completed && $0.date.isSameDay(as: day) }
                .compactMap(\.value)
            return activity.aggregateDayValue(from: values)

        case .container:
            let children = scheduleEngine.applicableChildren(for: activity, on: day, allActivities: allActivities, logs: allLogs)
            guard !children.isEmpty else { return 0 }
            let completedSum = children.reduce(0.0) { sum, child in
                let childLogs = allLogs.filter {
                    $0.activity?.id == child.id && $0.status == .completed && $0.date.isSameDay(as: day)
                }
                let sessions = child.sessionsPerDay(on: day)
                let done = min(childLogs.count, sessions)
                return sum + Double(done) / Double(max(sessions, 1))
            }
            return completedSum / Double(children.count) * 100

        case .metric:
            let dayMetrics = activityLogs
                .filter { $0.status == .completed && $0.date.isSameDay(as: day) }
                .compactMap(\.value)
            guard !dayMetrics.isEmpty else { return 0 }
            return dayMetrics.reduce(0, +) / Double(dayMetrics.count)
        }
    }

    private var chartUnit: String {
        switch activity.type {
        case .checkbox: return ""
        case .container: return "%"
        default: return activity.unit ?? ""
        }
    }

    // MARK: - Per-Activity Heatmap Data

    private var heatmapActivities: [Activity] {
        [activity]
    }

    // MARK: - Log History

    private var recentLogs: [ActivityLog] {
        activityLogs
            .sorted { $0.date > $1.date }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Streak Card
                streakCard

                // Range Picker (capsule buttons for 6 options)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Button {
                                selectedRange = range
                                offset = 0
                            } label: {
                                Text(range.rawValue)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedRange == range ? Color(hex: activity.hexColor) : Color(.tertiarySystemBackground))
                                    .foregroundStyle(selectedRange == range ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Bar Chart
                BarChartView(
                    bars: chartBars,
                    barColor: Color(hex: activity.hexColor),
                    unit: chartUnit,
                    dateLabel: chartDateLabel,
                    onPrevious: { offset -= 1 },
                    onNext: { offset += 1 },
                    canGoNext: offset < 0
                )

                // Heatmap
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Consistency", icon: "square.grid.3x3.fill")
                    HeatmapView(
                        activities: heatmapActivities,
                        allActivities: allActivities,
                        logs: allLogs,
                        vacationDays: vacationDays,
                        scheduleEngine: ScheduleEngine()
                    )
                }

                // Photo Lapse — only for photo metrics
                if activity.type == .metric && activity.metricKind == .photo {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("Photo Progress", icon: "timelapse")
                        PhotoLapseView(
                            activityID: activity.id,
                            activityColor: activity.hexColor,
                            photoSlots: activity.photoSlots
                        )
                    }
                }

                // Log History
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("History", icon: "list.bullet")

                    if recentLogs.isEmpty {
                        Text("No logs yet")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(recentLogs.prefix(30)) { log in
                            logRow(log)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .navigationTitle(activity.name)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Sub-views

    private var streakCard: some View {
        HStack(spacing: 0) {
            streakStat(label: "Current Streak", value: currentStreakValue, icon: "flame.fill", color: .orange)
            Divider().frame(height: 36)
            streakStat(label: "Longest Streak", value: longestStreakValue, icon: "trophy.fill", color: .yellow)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func streakStat(label: String, value: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(value > 0 ? color : Color.gray.opacity(0.3))

            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)d")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

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

    private func logRow(_ log: ActivityLog) -> some View {
        HStack(spacing: 10) {
            // Status icon
            Image(systemName: log.status == .completed ? "checkmark.circle.fill" : "forward.fill")
                .font(.system(size: 14))
                .foregroundStyle(log.status == .completed ? .green : .orange)

            // Date
            Text(log.date.shortDisplay)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Value if present
            if let value = log.value {
                Text(formatLogValue(value))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
            }

            // Skip reason
            if let reason = log.skipReason, !reason.isEmpty {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }

            // Note indicator
            if log.note != nil {
                Image(systemName: "note.text")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formatLogValue(_ val: Double) -> String {
        let unit = activity.unit ?? ""
        let numStr = val.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", val)
            : String(format: "%.1f", val)
        return unit.isEmpty ? numStr : "\(numStr) \(unit)"
    }
}
