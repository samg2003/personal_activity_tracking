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
    @State private var cachedDayCells: [DayCell] = []
    @State private var cachedMonthMarkers: [(label: String, weekIndex: Int)] = []
    @State private var isLoaded = false

    private let columns = 7
    private let totalDays = 91 // 13 weeks

    struct DayCell: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let completion: Double
        let isVacation: Bool
        let isSkippedDay: Bool
    }

    var body: some View {
        Group {
            if !isLoaded {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(height: 200)
                    .overlay { ProgressView().tint(.secondary) }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    monthLabelsRow

                    HStack(spacing: 4) {
                        let weekdays = ["M", "T", "W", "T", "F", "S", "S"]
                        ForEach(Array(weekdays.enumerated()), id: \.offset) { _, day in
                            Text(day)
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
                        ForEach(cachedDayCells) { cell in
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

                    legendRow

                    if let day = selectedDay {
                        tooltipCard(day)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
        }
        .task { await computeCells() }
    }

    private func computeCells() async {
        await Task.yield()
        let calendar = Calendar.current
        let today = Date().startOfDay

        // Pre-index logs by date for O(1) per-day lookup (replaces 91 × O(n) filtering)
        let logsByDate: [Date: [ActivityLog]] = Dictionary(grouping: logs) { $0.date.startOfDay }
        let vacationSet = Set(vacationDays.map { $0.date.startOfDay })

        var cells: [DayCell] = []
        cells.reserveCapacity(totalDays)

        for offset in stride(from: totalDays - 1, through: 0, by: -1) {
            // Yield every 15 days to keep UI responsive
            if offset % 15 == 0 && offset < totalDays - 1 { await Task.yield() }

            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let day = date.startOfDay
            if day > today {
                cells.append(DayCell(date: day, completion: 0, isVacation: false, isSkippedDay: false))
                continue
            }

            let isVacation = vacationSet.contains(day)
            let dayLogs = logsByDate[day] ?? []

            // Determine scheduled activities for this day
            let scheduled: [Activity]
            if activities.count == 1, let activity = activities.first {
                guard scheduleEngine.shouldShow(activity, on: date) else {
                    cells.append(DayCell(date: day, completion: 0, isVacation: isVacation, isSkippedDay: false))
                    continue
                }
                scheduled = [activity]
            } else {
                scheduled = scheduleEngine.activitiesForToday(from: activities, on: date, vacationDays: vacationDays)
                guard !scheduled.isEmpty else {
                    cells.append(DayCell(date: day, completion: 0, isVacation: isVacation, isSkippedDay: false))
                    continue
                }
            }

            // Compute completion rate using pre-filtered dayLogs
            var total = 0.0
            var done = 0.0
            var skippedCount = 0

            for activity in scheduled {
                let actLogs = dayLogs.filter { $0.activity?.id == activity.id }

                if activity.type == .container {
                    let children = scheduleEngine.applicableChildren(for: activity, on: date, allActivities: allActivities, logs: logs)
                    for child in children {
                        computeSlots(child, actLogs: dayLogs.filter { $0.activity?.id == child.id }, on: date, total: &total, done: &done, skippedCount: &skippedCount)
                    }
                } else if activity.type == .cumulative && (activity.targetValue == nil || activity.targetValue == 0) {
                    if actLogs.contains(where: { $0.status == .skipped }) { skippedCount += 1 }
                } else {
                    computeSlots(activity, actLogs: actLogs, on: date, total: &total, done: &done, skippedCount: &skippedCount)
                }
            }

            let allSkipped = total <= 0 && skippedCount > 0
            let rate = total > 0 ? done / total : 0
            cells.append(DayCell(date: day, completion: max(rate, 0), isVacation: isVacation, isSkippedDay: allSkipped))
        }

        cachedDayCells = cells

        // Build month markers from cached cells
        var markers: [(String, Int)] = []
        var lastMonth = -1
        for (index, cell) in cachedDayCells.enumerated() {
            let month = calendar.component(.month, from: cell.date)
            if month != lastMonth {
                let weekIdx = index / columns
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM"
                markers.append((formatter.string(from: cell.date), weekIdx))
                lastMonth = month
            }
        }
        cachedMonthMarkers = markers
        isLoaded = true
    }

    /// Inline slot computation for heatmap — avoids re-filtering logs
    private func computeSlots(_ activity: Activity, actLogs: [ActivityLog], on date: Date, total: inout Double, done: inout Double, skippedCount: inout Int) {
        let slots = activity.timeSlotsActive(on: date)
        let sessions = activity.sessionsPerDay(on: date)

        if slots.count > 1 {
            var slotsDone = 0
            var slotsSkipped = 0
            for slot in slots {
                if actLogs.contains(where: { $0.status == .completed && $0.timeSlot == slot }) {
                    slotsDone += 1
                } else if actLogs.contains(where: { $0.status == .skipped && $0.timeSlot == slot }) {
                    slotsSkipped += 1
                }
            }
            if slotsSkipped == sessions && slotsDone == 0 {
                skippedCount += 1
            } else {
                total += Double(sessions - slotsSkipped)
                done += Double(min(slotsDone, sessions - slotsSkipped))
            }
        } else {
            let dayCompleted = actLogs.filter { $0.status == .completed }.count
            let daySkipped = actLogs.contains { $0.status == .skipped }
            if daySkipped && dayCompleted == 0 {
                skippedCount += 1
            } else {
                total += Double(sessions)
                done += Double(min(dayCompleted, sessions))
            }
        }
    }

    // MARK: - Sub-views

    private var monthLabelsRow: some View {
        HStack(spacing: 0) {
            ForEach(cachedMonthMarkers, id: \.weekIndex) { marker in
                Text(marker.label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                if marker.weekIndex != cachedMonthMarkers.last?.weekIndex {
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
