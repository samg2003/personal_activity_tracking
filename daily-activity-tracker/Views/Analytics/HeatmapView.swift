import SwiftUI
import SwiftData

/// Completion heatmap — shows a grid of recent days colored by completion percentage
struct HeatmapView: View {
    let activities: [Activity]
    let logs: [ActivityLog]
    let vacationDays: [VacationDay]

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
            let dayLogs = logs.filter { $0.date.isSameDay(as: date) }
            let applicable = activities.filter { $0.parent == nil && !$0.isArchived }

            let completedCount = applicable.filter { activity in
                dayLogs.contains { $0.activity?.id == activity.id && $0.status == .completed }
            }.count
            let skippedCount = applicable.filter { activity in
                dayLogs.contains { $0.activity?.id == activity.id && $0.status == .skipped }
            }.count

            // Strict: yellow only if ALL applicable activities are skipped (and none completed)
            let allSkipped = !applicable.isEmpty && skippedCount == applicable.count && completedCount == 0
            let completion = applicable.isEmpty ? 0 : Double(completedCount) / Double(applicable.count)
            return DayCell(date: date, completion: completion, isVacation: isVacation, isSkippedDay: allSkipped)
        }.reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Weekday labels
            HStack(spacing: 4) {
                let weekdays = ["M", "T", "W", "T", "F", "S", "S"]
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
                ForEach(dayCells) { cell in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(cellColor(cell))
                        .frame(height: 14)
                        .overlay {
                            if cell.isVacation {
                                Image(systemName: "airplane")
                                    .font(.system(size: 6))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .onTapGesture { selectedDay = cell }
                }
            }

            // Selected day tooltip
            if let day = selectedDay {
                HStack {
                    Text(day.date.shortDisplay)
                        .font(.caption)
                    Spacer()
                    if day.isVacation {
                        Text("Vacation")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    } else {
                        Text("\(Int(day.completion * 100))% complete")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func cellColor(_ cell: DayCell) -> Color {
        if cell.isVacation { return .blue.opacity(0.3) }
        if cell.date > Date().startOfDay { return Color(.systemGray6) }
        if cell.isSkippedDay { return .orange.opacity(0.4) }
        return .green.opacity(max(cell.completion * 0.8 + 0.1, 0.08))
    }
}
