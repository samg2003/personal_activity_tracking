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

    // MARK: - Filtered logs for this activity

    private var activityLogs: [ActivityLog] {
        allLogs.filter { $0.activity?.id == activity.id }
    }

    /// Logs including children (for containers)
    private var effectiveLogs: [ActivityLog] {
        if activity.type == .container {
            let childIDs = Set(activity.children.filter { !$0.isArchived }.map(\.id))
            return allLogs.filter { log in
                guard let aid = log.activity?.id else { return false }
                return childIDs.contains(aid)
            }
        }
        return activityLogs
    }

    // MARK: - Streak Computation

    private var currentStreak: Int {
        computeStreak()
    }

    private var longestStreak: Int {
        guard let earliest = activity.createdAt ?? activityLogs.map(\.date).min() else { return 0 }
        let completedDates: Set<Date>
        let skippedDates = Set(
            activityLogs.filter { $0.status == .skipped }.map { $0.date.startOfDay }
        )

        if activity.type == .container {
            var dates = Set<Date>()
            var day = Date().startOfDay
            while day >= earliest.startOfDay {
                if isContainerCompleted(on: day) { dates.insert(day) }
                guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
                day = prev
            }
            completedDates = dates
        } else {
            completedDates = Set(
                activityLogs.filter { $0.status == .completed }.map { $0.date.startOfDay }
            )
        }

        var maxStreak = 0
        var current = 0
        var day = Date().startOfDay

        while day >= earliest.startOfDay {
            if day < activity.createdDate.startOfDay { break }
            if let stopped = activity.stoppedAt, day > stopped { break }

            let schedule = activity.scheduleActive(on: day)
            let isScheduled: Bool
            switch schedule.type {
            case .daily: isScheduled = true
            case .weekly: isScheduled = (schedule.weekdays ?? []).contains(day.weekdayISO)
            case .monthly: isScheduled = (schedule.monthDays ?? []).contains(day.dayOfMonth)
            default: isScheduled = false
            }

            if !isScheduled || vacationDays.contains(where: { $0.date.isSameDay(as: day) }) {
                // not scheduled or vacation — pass through
            } else if completedDates.contains(day) {
                current += 1
                maxStreak = max(maxStreak, current)
            } else if skippedDates.contains(day) {
                // explicitly skipped — pass through
            } else {
                current = 0
            }

            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }

        return maxStreak
    }

    private func computeStreak() -> Int {
        if activity.type == .container {
            return computeContainerStreak()
        }

        let completedDates = Set(
            activityLogs.filter { $0.status == .completed }.map { $0.date.startOfDay }
        )
        let skippedDates = Set(
            activityLogs.filter { $0.status == .skipped }.map { $0.date.startOfDay }
        )

        var streak = 0
        var day = Date().startOfDay
        if !completedDates.contains(day) {
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = prev
        }

        for _ in 0..<3650 {
            if day < activity.createdDate.startOfDay { break }
            if let stopped = activity.stoppedAt, day > stopped { break }

            let schedule = activity.scheduleActive(on: day)
            let isScheduled: Bool
            switch schedule.type {
            case .daily: isScheduled = true
            case .weekly: isScheduled = (schedule.weekdays ?? []).contains(day.weekdayISO)
            case .monthly: isScheduled = (schedule.monthDays ?? []).contains(day.dayOfMonth)
            default: isScheduled = false
            }

            if !isScheduled {
                // not scheduled — pass through
            } else if completedDates.contains(day) {
                streak += 1
            } else if vacationDays.contains(where: { $0.date.isSameDay(as: day) }) {
                // vacation — pass through
            } else if skippedDates.contains(day) {
                // explicitly skipped — pass through
            } else {
                break
            }

            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    private func computeContainerStreak() -> Int {
        let skippedDates = Set(
            effectiveLogs.filter { $0.status == .skipped }.map { $0.date.startOfDay }
        )
        var streak = 0
        var day = Date().startOfDay
        if !isContainerCompleted(on: day) {
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = prev
        }
        for _ in 0..<3650 {
            if day < activity.createdDate.startOfDay { break }
            let schedule = activity.scheduleActive(on: day)
            let isScheduled: Bool
            switch schedule.type {
            case .daily: isScheduled = true
            case .weekly: isScheduled = (schedule.weekdays ?? []).contains(day.weekdayISO)
            case .monthly: isScheduled = (schedule.monthDays ?? []).contains(day.dayOfMonth)
            default: isScheduled = false
            }
            if !isScheduled {
                // not scheduled — pass through
            } else if isContainerCompleted(on: day) {
                streak += 1
            } else if vacationDays.contains(where: { $0.date.isSameDay(as: day) }) {
                // vacation — pass through
            } else if skippedDates.contains(day) {
                // explicitly skipped — pass through
            } else {
                break
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    private func isContainerCompleted(on day: Date) -> Bool {
        let children = activity.children.filter { !$0.isArchived }
        guard !children.isEmpty else { return false }
        return children.allSatisfy { child in
            allLogs.contains {
                $0.activity?.id == child.id && $0.status == .completed && $0.date.isSameDay(as: day)
            }
        }
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
            case .value, .metric:
                let nonZero = values.filter { $0 > 0 }
                aggregate = nonZero.isEmpty ? 0 : nonZero.reduce(0, +) / Double(nonZero.count) // weekly avg
            case .cumulative:
                aggregate = values.reduce(0, +) // weekly sum
            case .container:
                let nonZero = values.filter { $0 > 0 }
                aggregate = nonZero.isEmpty ? 0 : nonZero.reduce(0, +) / Double(nonZero.count) // avg %
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
            return activityLogs
                .filter { $0.status == .completed && $0.date.isSameDay(as: day) }
                .compactMap(\.value)
                .last ?? 0

        case .cumulative:
            return activityLogs
                .filter { $0.status == .completed && $0.date.isSameDay(as: day) }
                .compactMap(\.value)
                .reduce(0, +)

        case .container:
            let children = activity.children.filter { !$0.isArchived }
            guard !children.isEmpty else { return 0 }
            let completed = children.filter { child in
                allLogs.contains {
                    $0.activity?.id == child.id && $0.status == .completed && $0.date.isSameDay(as: day)
                }
            }.count
            return Double(completed) / Double(children.count) * 100

        case .metric:
            return activityLogs
                .filter { $0.status == .completed && $0.date.isSameDay(as: day) }
                .compactMap(\.value)
                .last ?? 0
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
                        logs: allLogs,
                        vacationDays: vacationDays
                    )
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
            streakStat(label: "Current Streak", value: currentStreak, icon: "flame.fill", color: .orange)
            Divider().frame(height: 36)
            streakStat(label: "Longest Streak", value: longestStreak, icon: "trophy.fill", color: .yellow)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
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
        .background(Color(.secondarySystemBackground))
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
