import SwiftUI

/// Horizontal scrollable date picker for browsing past days.
/// Starts with 14 days visible and dynamically loads more when the user taps the left-arrow.
struct DatePickerBar: View {
    @Binding var selectedDate: Date
    var vacationDays: [VacationDay] = []
    var allLogs: [ActivityLog] = []
    var allActivities: [Activity] = []
    var scheduleEngine: ScheduleEngineProtocol = ScheduleEngine()

    @State private var daysToShow = 14
    private let pageSize = 14

    private var dates: [Date] {
        let calendar = Calendar.current
        let today = Date().startOfDay
        return (0..<daysToShow).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }.reversed()
    }
    
    private func isVacation(_ date: Date) -> Bool {
        vacationDays.contains { $0.date.isSameDay(as: date) }
    }

    private func completionStatus(_ date: Date) -> (rate: Double, allSkipped: Bool) {
        let status = scheduleEngine.completionStatus(on: date, activities: allActivities, allActivities: allActivities, logs: allLogs, vacationDays: vacationDays)
        return (status.rate, status.allSkipped)
    }

    /// Dot color below the date number indicating completion
    private func dotColor(_ date: Date) -> Color? {
        if isVacation(date) { return .blue }
        let status = completionStatus(date)
        if status.rate < 0 { return nil }
        if status.allSkipped { return .orange }
        if status.rate >= 1.0 { return .green }
        if status.rate > 0 { return Color(hex: 0xF59E0B) }
        return nil
    }

    /// Background tint for non-selected chips based on completion
    private func chipBackground(_ date: Date) -> Color {
        if isVacation(date) { return .blue.opacity(0.15) }
        let status = completionStatus(date)
        if status.rate < 0 { return Color(.systemGray6).opacity(0.5) }
        if status.allSkipped { return .orange.opacity(0.15) }
        if status.rate >= 1.0 { return .green.opacity(0.2) }
        if status.rate > 0 { return .green.opacity(0.08 + status.rate * 0.12) }
        return Color(.systemGray6).opacity(0.5)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    loadMoreButton(proxy: proxy)

                    ForEach(Array(dates.enumerated()), id: \.element.timeIntervalSince1970) { index, date in
                        if isMonthBoundary(at: index) {
                            monthLabel(for: date)
                        }
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
                let calendar = Calendar.current
                if let earliest = dates.first,
                   newDate.startOfDay < earliest.startOfDay {
                    let daysBack = calendar.dateComponents([.day], from: newDate.startOfDay, to: Date().startOfDay).day ?? 0
                    daysToShow = max(daysToShow, daysBack + pageSize)
                }
                withAnimation {
                    proxy.scrollTo(newDate.startOfDay, anchor: .center)
                }
            }
        }
    }

    private func loadMoreButton(proxy: ScrollViewProxy) -> some View {
        Button {
            let oldEarliest = dates.first
            withAnimation(.easeInOut(duration: 0.2)) {
                daysToShow += pageSize
            }
            if let anchor = oldEarliest {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    proxy.scrollTo(anchor.startOfDay, anchor: .leading)
                }
            }
        } label: {
            Image(systemName: "chevron.left.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 56)
        }
        .buttonStyle(.plain)
    }

    private func isMonthBoundary(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let calendar = Calendar.current
        return calendar.component(.month, from: dates[index]) != calendar.component(.month, from: dates[index - 1])
    }

    private func monthLabel(for date: Date) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        let label = formatter.string(from: date).uppercased()
        return Text(label)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(-90))
            .frame(width: 16, height: 56)
    }

    private func dateChip(_ date: Date) -> some View {
        let isSelected = date.isSameDay(as: selectedDate)
        let isToday = date.isSameDay(as: Date())
        let vacation = isVacation(date)
        let calendar = Calendar.current
        let dot = dotColor(date)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDate = date
            }
        } label: {
            VStack(spacing: 3) {
                if vacation {
                    Text("✈️")
                        .font(.system(size: 10))
                } else {
                    Text(dayAbbreviation(date))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color(.tertiaryLabel))
                }

                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 15, weight: isSelected ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : (isToday ? Color(hex: 0x10B981) : Color(.label)))

                // Completion dot
                if let dot, !isSelected {
                    Circle()
                        .fill(dot)
                        .frame(width: 5, height: 5)
                } else if isToday && !isSelected {
                    Text("Today")
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: 0x10B981))
                } else {
                    Spacer().frame(height: 5)
                }
            }
            .frame(width: 44, height: 56)
            .background(
                Group {
                    if isSelected {
                        if vacation {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.blue)
                                .shadow(color: Color.blue.opacity(0.3), radius: 6, y: 3)
                        } else {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: 0x10B981), Color(hex: 0x0D9488)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                .shadow(color: Color(hex: 0x10B981).opacity(0.3), radius: 6, y: 3)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(chipBackground(date))
                    }
                }
            )
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(hex: 0x10B981), lineWidth: 1.5)
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
