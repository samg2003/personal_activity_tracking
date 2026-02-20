import SwiftUI
import SwiftData

/// Completion heatmap — GitHub-style contribution graph with rounded cells, month labels, and legend
struct HeatmapView: View {
    let activities: [Activity]
    let allActivities: [Activity]
    let logs: [ActivityLog]
    let vacationDays: [VacationDay]
    let scheduleEngine: ScheduleEngine

    @State private var selectedDay: DayCell?

    private let columns = 7
    private let totalDays = 91 // 13 weeks

    struct DayCell: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let completion: Double
        let isVacation: Bool
        let isSkippedDay: Bool
    }

    private var dayCells: [DayCell] {
        let calendar = Calendar.current
        let today = Date().startOfDay
        return (0..<totalDays).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let isVacation = vacationDays.contains { $0.date.isSameDay(as: date) }
            let status = scheduleEngine.completionStatus(on: date, activities: activities, allActivities: allActivities, logs: logs, vacationDays: vacationDays)
            return DayCell(date: date, completion: max(status.rate, 0), isVacation: isVacation, isSkippedDay: status.allSkipped)
        }.reversed()
    }

    /// Month labels positioned above the grid
    private var monthMarkers: [(label: String, weekIndex: Int)] {
        let calendar = Calendar.current
        var markers: [(String, Int)] = []
        var lastMonth = -1
        for (index, cell) in dayCells.enumerated() {
            let month = calendar.component(.month, from: cell.date)
            if month != lastMonth {
                let weekIdx = index / columns
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM"
                markers.append((formatter.string(from: cell.date), weekIdx))
                lastMonth = month
            }
        }
        return markers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Month labels row
            monthLabelsRow

            // Weekday labels
            HStack(spacing: 4) {
                let weekdays = ["M", "T", "W", "T", "F", "S", "S"]
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
                ForEach(dayCells) { cell in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(cellColor(cell))
                        .frame(height: 18)
                        .overlay {
                            if cell.isVacation {
                                Image(systemName: "airplane")
                                    .font(.system(size: 7, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        .overlay {
                            if let sel = selectedDay, sel.id == cell.id {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.primary.opacity(0.5), lineWidth: 1.5)
                            }
                        }
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedDay = selectedDay?.id == cell.id ? nil : cell
                            }
                        }
                }
            }

            // Legend
            legendRow

            // Selected day tooltip
            if let day = selectedDay {
                tooltipCard(day)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // MARK: - Sub-views

    private var monthLabelsRow: some View {
        HStack(spacing: 0) {
            ForEach(monthMarkers, id: \.weekIndex) { marker in
                Text(marker.label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                if marker.weekIndex != monthMarkers.last?.weekIndex {
                    Spacer()
                }
            }
        }
    }

    private var legendRow: some View {
        HStack(spacing: 4) {
            Spacer()
            Text("Less")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                RoundedRectangle(cornerRadius: 3)
                    .fill(greenForLevel(level))
                    .frame(width: 12, height: 12)
            }
            Text("More")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private func tooltipCard(_ day: DayCell) -> some View {
        HStack {
            Text(day.date.shortDisplay)
                .font(.caption.weight(.medium))
            Spacer()
            if day.isVacation {
                Label("Vacation", systemImage: "airplane")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.blue)
            } else if day.isSkippedDay {
                Label("Skipped", systemImage: "forward.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            } else {
                Text("\(Int(day.completion * 100))% complete")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(day.completion >= 1.0 ? .green : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        )
    }

    // MARK: - Colors

    private func cellColor(_ cell: DayCell) -> Color {
        if cell.isVacation { return .blue.opacity(0.35) }
        if cell.date > Date().startOfDay { return Color(.systemGray6) }
        if cell.isSkippedDay { return .orange.opacity(0.45) }
        return greenForLevel(cell.completion)
    }

    private func greenForLevel(_ level: Double) -> Color {
        if level <= 0 { return Color(.systemGray5) }
        // Use a gradient from light green to saturated green
        let hue = 0.35
        let saturation = 0.4 + level * 0.4
        let brightness = 0.95 - level * 0.35
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}
