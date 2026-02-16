import SwiftUI

/// Horizontal scrollable date picker for browsing past days
struct DatePickerBar: View {
    @Binding var selectedDate: Date
    var vacationDays: [VacationDay] = []
    var allLogs: [ActivityLog] = []
    var allActivities: [Activity] = []
    var scheduleEngine: ScheduleEngineProtocol = ScheduleEngine()

    private let visibleDays = 14

    private var dates: [Date] {
        let calendar = Calendar.current
        let today = Date().startOfDay
        return (0..<visibleDays).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }.reversed()
    }
    
    private func isVacation(_ date: Date) -> Bool {
        vacationDays.contains { $0.date.isSameDay(as: date) }
    }

    /// Compute completion fraction for a given date (0…1, or -1 if no activities)
    /// Completion status for a date: (fraction 0…1, allSkipped flag). Returns (-1, false) if no scheduled activities.
    private func completionStatus(_ date: Date) -> (rate: Double, allSkipped: Bool) {
        if date.startOfDay > Date().startOfDay { return (-1, false) }
        let scheduled = scheduleEngine.activitiesForToday(from: allActivities, on: date, vacationDays: vacationDays, logs: allLogs)
        guard !scheduled.isEmpty else { return (-1, false) }

        let dayLogs = allLogs.filter { $0.date.isSameDay(as: date) }
        var total = 0.0
        var done = 0.0
        var skippedCount = 0

        for activity in scheduled {
            let actSkipped = dayLogs.contains {
                $0.activity?.id == activity.id && $0.status == .skipped
            }

            if activity.type == .container {
                let children = activity.historicalChildren(on: date, from: allActivities)
                for child in children {
                    let childSkipped = dayLogs.contains {
                        $0.activity?.id == child.id && $0.status == .skipped
                    }
                    if childSkipped { skippedCount += 1; continue }
                    total += 1
                    if dayLogs.contains(where: { $0.activity?.id == child.id && $0.status == .completed }) {
                        done += 1
                    }
                }
            } else if activity.type == .cumulative && (activity.targetValue == nil || activity.targetValue == 0) {
                // No-target cumulative: still track as skipped if applicable
                if actSkipped { skippedCount += 1 }
            } else if actSkipped {
                skippedCount += 1
            } else if activity.type == .cumulative, let target = activity.targetValue, target > 0 {
                // Partial credit for cumulative
                total += 1.0
                let values = dayLogs
                    .filter { $0.activity?.id == activity.id && $0.status == .completed }
                    .compactMap(\.value)
                let cumVal = activity.aggregateDayValue(from: values)
                done += min(cumVal / target, 1.0)
            } else {
                let sessions = Double(activity.sessionsPerDay(on: date))
                total += sessions
                let completedCount = Double(dayLogs.filter {
                    $0.activity?.id == activity.id && $0.status == .completed
                }.count)
                done += min(completedCount, sessions)
            }
        }

        if total <= 0 && skippedCount > 0 { return (0, true) }
        guard total > 0 else { return (-1, false) }
        return (done / total, false)
    }

    /// Background tint color based on completion status
    private func completionBackgroundColor(_ date: Date) -> Color {
        if isVacation(date) { return .blue.opacity(0.2) }
        let status = completionStatus(date)
        if status.rate < 0 { return Color(.secondarySystemBackground) }
        if status.allSkipped { return .orange.opacity(0.2) }
        if status.rate >= 1.0 { return .green.opacity(0.3) }
        if status.rate > 0 { return .green.opacity(0.12 + status.rate * 0.15) }
        return Color(.systemGray5)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(dates, id: \.timeIntervalSince1970) { date in
                        dateChip(date)
                            .id(date.startOfDay)
                    }
                }
                .padding(.horizontal)
            }
            .onAppear {
                proxy.scrollTo(selectedDate.startOfDay, anchor: .trailing)
            }
            .onChange(of: selectedDate) { _, newDate in
                withAnimation {
                    proxy.scrollTo(newDate.startOfDay, anchor: .center)
                }
            }
        }
    }

    private func dateChip(_ date: Date) -> some View {
        let isSelected = date.isSameDay(as: selectedDate)
        let isToday = date.isSameDay(as: Date())
        let vacation = isVacation(date)
        let calendar = Calendar.current
        let bgColor = completionBackgroundColor(date)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDate = date
            }
        } label: {
            VStack(spacing: 4) {
                if vacation {
                    Text("✈️")
                        .font(.system(size: 10))
                } else {
                    Text(dayAbbreviation(date))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white : Color(.tertiaryLabel))
                }

                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 16, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : Color(.label)))
            }
            .frame(width: 42, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(vacation && isSelected ? Color.blue : (isSelected ? Color.accentColor : bgColor))
            )
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func dayAbbreviation(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).prefix(3).uppercased()
    }
}

