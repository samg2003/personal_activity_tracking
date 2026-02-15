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
    private func completionForDate(_ date: Date) -> Double {
        if date.startOfDay > Date().startOfDay { return -1 }
        let scheduled = scheduleEngine.activitiesForToday(from: allActivities, on: date, vacationDays: vacationDays, logs: allLogs)
        guard !scheduled.isEmpty else { return -1 }

        let dayLogs = allLogs.filter { $0.date.isSameDay(as: date) }
        var total = 0
        var done = 0

        for activity in scheduled {
            let isSkipped = dayLogs.contains {
                $0.activity?.id == activity.id && $0.status == .skipped
            }
            if isSkipped { continue }

            if activity.type == .container {
                let children = activity.children.filter { !$0.isArchived }
                for child in children {
                    let childSkipped = dayLogs.contains {
                        $0.activity?.id == child.id && $0.status == .skipped
                    }
                    if childSkipped { continue }
                    total += 1
                    if dayLogs.contains(where: { $0.activity?.id == child.id && $0.status == .completed }) {
                        done += 1
                    }
                }
            } else {
                let sessions = activity.sessionsPerDay(on: date)
                total += sessions
                let completedCount = dayLogs.filter {
                    $0.activity?.id == activity.id && $0.status == .completed
                }.count
                done += min(completedCount, sessions)
            }
        }

        guard total > 0 else { return -1 }
        return Double(done) / Double(total)
    }

    /// Color indicator for completion rate
    private func completionIndicatorColor(_ date: Date) -> Color? {
        if isVacation(date) { return .blue }
        let rate = completionForDate(date)
        if rate < 0 { return nil }
        if rate >= 1.0 { return .green }
        if rate > 0 { return .orange }
        return Color(.systemGray4)
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
        let indicator = completionIndicatorColor(date)

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

                // Completion indicator dot
                if !isSelected, let color = indicator {
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 5, height: 5)
                }
            }
            .frame(width: 42, height: 58)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(vacation && isSelected ? Color.blue : (isSelected ? Color.accentColor : Color(.secondarySystemBackground)))
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

