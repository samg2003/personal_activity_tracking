import SwiftUI
import SwiftData

/// Line chart showing value trends for a specific activity over time
struct ValueChartView: View {
    let activity: Activity
    let logs: [ActivityLog]

    enum TimeRange: String, CaseIterable {
        case week = "7D"
        case month = "30D"
        case quarter = "90D"
        case halfYear = "6M"
        case year = "1Y"
        case threeYear = "3Y"

        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            case .halfYear: return 180
            case .year: return 365
            case .threeYear: return 1095
            }
        }

        var useWeeklyAggregation: Bool {
            self == .halfYear || self == .year || self == .threeYear
        }
    }

    @State private var selectedRange: TimeRange = .month

    /// Logs are expected to be pre-filtered for this activity by the caller
    private var filteredLogs: [ActivityLog] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -selectedRange.days, to: Date()) ?? Date()
        return logs
            .filter {
                $0.status == .completed
                && $0.value != nil
                && $0.date >= cutoff
            }
            .sorted { $0.date < $1.date }
    }

    /// Data points: daily for short ranges, weekly-aggregated for 6M+
    private var chartPoints: [(date: Date, value: Double)] {
        if selectedRange.useWeeklyAggregation {
            return weeklyPoints
        }
        return dailyPoints
    }

    /// Aggregate daily values
    private var dailyPoints: [(date: Date, value: Double)] {
        let grouped = Dictionary(grouping: filteredLogs) { $0.date.startOfDay }
        return grouped.map { (date, dayLogs) in
            let value: Double
            if activity.type == .cumulative {
                value = activity.aggregateDayValue(from: dayLogs.compactMap(\.value))
            } else {
                let values = dayLogs.compactMap(\.value)
                value = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
            }
            return (date, value)
        }
        .sorted { $0.date < $1.date }
    }

    /// Weekly-aggregated points for wider ranges — averages daily values across each week
    private var weeklyPoints: [(date: Date, value: Double)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredLogs) { log in
            calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: log.date))!
        }
        return grouped.map { (weekStart, weekLogs) in
            // First compute per-day values
            let byDay = Dictionary(grouping: weekLogs.filter { $0.status == .completed }) { $0.date.startOfDay }
            let dailyValues: [Double] = byDay.values.compactMap { dayLogs in
                let vals = dayLogs.compactMap(\.value)
                guard !vals.isEmpty else { return nil }
                if activity.type == .cumulative {
                    return activity.aggregateDayValue(from: vals)
                } else {
                    return vals.reduce(0, +) / Double(vals.count)
                }
            }
            guard !dailyValues.isEmpty else { return (weekStart, 0.0) }
            // Then average across days
            let value = dailyValues.reduce(0, +) / Double(dailyValues.count)
            return (weekStart, value)
        }
        .sorted { $0.date < $1.date }
    }

    private var maxValue: Double { chartPoints.map(\.value).max() ?? 1 }
    private var minValue: Double { chartPoints.map(\.value).min() ?? 0 }
    private var avgValue: Double {
        guard !chartPoints.isEmpty else { return 0 }
        return chartPoints.map(\.value).reduce(0, +) / Double(chartPoints.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: activity.icon)
                    .foregroundStyle(Color(hex: activity.hexColor))
                Text(activity.name)
                    .font(.subheadline.bold())
                Spacer()

                // Range picker (capsule buttons)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Button {
                                selectedRange = range
                            } label: {
                                Text(range.rawValue)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(selectedRange == range ? Color(hex: activity.hexColor) : Color(.tertiarySystemBackground))
                                    .foregroundStyle(selectedRange == range ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if chartPoints.isEmpty {
                Text("No data yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
            } else {
                // Chart area
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height - 20
                    let range = maxValue - minValue
                    let effectiveRange = range > 0 ? range : 1

                    ZStack(alignment: .topLeading) {
                        // Average line
                        let avgY = h - CGFloat((avgValue - minValue) / effectiveRange) * h
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: avgY))
                            path.addLine(to: CGPoint(x: w, y: avgY))
                        }
                        .stroke(.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        // Line path
                        Path { path in
                            for (i, point) in chartPoints.enumerated() {
                                let x = chartPoints.count == 1 ? w / 2 : w * CGFloat(i) / CGFloat(chartPoints.count - 1)
                                let y = h - CGFloat((point.value - minValue) / effectiveRange) * h

                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(Color(hex: activity.hexColor), lineWidth: 2)

                        // Dots
                        ForEach(Array(chartPoints.enumerated()), id: \.offset) { i, point in
                            let x = chartPoints.count == 1 ? w / 2 : w * CGFloat(i) / CGFloat(chartPoints.count - 1)
                            let y = h - CGFloat((point.value - minValue) / effectiveRange) * h
                            Circle()
                                .fill(Color(hex: activity.hexColor))
                                .frame(width: 5, height: 5)
                                .position(x: x, y: y)
                        }

                        // Y-axis labels
                        VStack {
                            Text(formatValue(maxValue))
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text(formatValue(minValue))
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(height: h)
                    }
                }
                .frame(height: 140)

                // Stats row
                HStack {
                    statBadge("Avg", value: avgValue)
                    statBadge("High", value: maxValue)
                    statBadge("Low", value: minValue)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func statBadge(_ label: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text("\(formatValue(value)) \(activity.unit ?? "")")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatValue(_ val: Double) -> String {
        val.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", val)
            : String(format: "%.1f", val)
    }
}
