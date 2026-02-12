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
    }

    @State private var selectedRange: TimeRange = .month

    private var filteredLogs: [ActivityLog] {
        let days: Int
        switch selectedRange {
        case .week: days = 7
        case .month: days = 30
        case .quarter: days = 90
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return logs
            .filter {
                $0.activity?.id == activity.id
                && $0.status == .completed
                && $0.value != nil
                && $0.date >= cutoff
            }
            .sorted { $0.date < $1.date }
    }

    /// Aggregate daily values (sum for cumulative, latest for value type)
    private var dailyPoints: [(date: Date, value: Double)] {
        let grouped = Dictionary(grouping: filteredLogs) { $0.date.startOfDay }
        return grouped.map { (date, dayLogs) in
            let value: Double
            if activity.type == .cumulative {
                value = dayLogs.reduce(0) { $0 + ($1.value ?? 0) }
            } else {
                value = dayLogs.last?.value ?? 0
            }
            return (date, value)
        }
        .sorted { $0.date < $1.date }
    }

    private var maxValue: Double { dailyPoints.map(\.value).max() ?? 1 }
    private var minValue: Double { dailyPoints.map(\.value).min() ?? 0 }
    private var avgValue: Double {
        guard !dailyPoints.isEmpty else { return 0 }
        return dailyPoints.map(\.value).reduce(0, +) / Double(dailyPoints.count)
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

                Picker("Range", selection: $selectedRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            if dailyPoints.isEmpty {
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
                            for (i, point) in dailyPoints.enumerated() {
                                let x = dailyPoints.count == 1 ? w / 2 : w * CGFloat(i) / CGFloat(dailyPoints.count - 1)
                                let y = h - CGFloat((point.value - minValue) / effectiveRange) * h

                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(Color(hex: activity.hexColor), lineWidth: 2)

                        // Dots
                        ForEach(Array(dailyPoints.enumerated()), id: \.offset) { i, point in
                            let x = dailyPoints.count == 1 ? w / 2 : w * CGFloat(i) / CGFloat(dailyPoints.count - 1)
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
        .background(Color(.secondarySystemBackground))
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
