import SwiftUI

/// Apple Health-style bar chart with day/week/month aggregation and swipeable time navigation
struct BarChartView: View {
    let bars: [BarData]
    let barColor: Color
    let unit: String
    let dateLabel: String
    let onPrevious: () -> Void
    let onNext: () -> Void
    let canGoNext: Bool

    @State private var selectedBar: BarData?

    struct BarData: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let value: Double
        let date: Date

        static func == (lhs: BarData, rhs: BarData) -> Bool {
            lhs.id == rhs.id
        }
    }

    private var maxValue: Double { max(bars.map(\.value).max() ?? 1, 0.01) }
    private var avgValue: Double {
        let nonZero = bars.filter { $0.value > 0 }
        guard !nonZero.isEmpty else { return 0 }
        return nonZero.map(\.value).reduce(0, +) / Double(nonZero.count)
    }
    private var totalValue: Double { bars.map(\.value).reduce(0, +) }

    var body: some View {
        VStack(spacing: 12) {
            // Time navigation header
            HStack {
                Button { onPrevious() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(dateLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button { onNext() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(canGoNext ? .secondary : .quaternary)
                }
                .disabled(!canGoNext)
            }
            .padding(.horizontal, 4)

            // Selected bar detail
            if let selected = selectedBar {
                HStack {
                    Text(selected.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatValue(selected.value) + (unit.isEmpty ? "" : " \(unit)"))
                        .font(.system(.caption, design: .rounded, weight: .bold))
                }
                .padding(.horizontal, 4)
                .transition(.opacity)
            }

            // Bar chart
            GeometryReader { geo in
                let spacing: CGFloat = bars.count > 15 ? 2 : 4
                let totalSpacing = spacing * CGFloat(max(bars.count - 1, 0))
                let barWidth = max((geo.size.width - totalSpacing) / CGFloat(max(bars.count, 1)), 2)
                let chartHeight = geo.size.height - 18 // leave room for labels

                ZStack(alignment: .bottom) {
                    // Average line
                    if avgValue > 0 {
                        let avgY = chartHeight * CGFloat(avgValue / maxValue)
                        VStack {
                            Spacer()
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(height: 1)
                                .offset(y: -avgY)
                        }
                        .frame(height: chartHeight)
                    }

                    // Bars + labels
                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(bars) { bar in
                            VStack(spacing: 2) {
                                // Bar
                                RoundedRectangle(cornerRadius: bars.count > 15 ? 1.5 : 3)
                                    .fill(
                                        selectedBar?.id == bar.id
                                            ? barColor
                                            : barColor.opacity(bar.value > 0 ? 0.7 : 0.15)
                                    )
                                    .frame(
                                        width: barWidth,
                                        height: max(
                                            bar.value > 0
                                                ? chartHeight * CGFloat(bar.value / maxValue)
                                                : 2,
                                            2
                                        )
                                    )

                                // Label
                                Text(bar.label)
                                    .font(.system(size: bars.count > 15 ? 6 : 9))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: barWidth)
                                    .lineLimit(1)
                            }
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedBar = selectedBar?.id == bar.id ? nil : bar
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: 130)

            // Stats row
            HStack {
                statLabel("Avg", value: avgValue, unit: unit)
                Divider().frame(height: 20)
                statLabel("Total", value: totalValue, unit: unit)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func statLabel(_ label: String, value: Double, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(formatValue(value) + (unit.isEmpty ? "" : " \(unit)"))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatValue(_ val: Double) -> String {
        if val == 0 { return "0" }
        if val >= 100 { return String(format: "%.0f", val) }
        return val.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", val)
            : String(format: "%.1f", val)
    }
}
