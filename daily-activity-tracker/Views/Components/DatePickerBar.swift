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

    /// Completion status for a date — delegates to centralized ScheduleEngine logic.
    private func completionStatus(_ date: Date) -> (rate: Double, allSkipped: Bool) {
        let status = scheduleEngine.completionStatus(on: date, activities: allActivities, allActivities: allActivities, logs: allLogs, vacationDays: vacationDays)
        return (status.rate, status.allSkipped)
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
                    // Load-more button at the leading edge
                    loadMoreButton(proxy: proxy)

                    ForEach(Array(dates.enumerated()), id: \.element.timeIntervalSince1970) { index, date in
                        // Show month label at boundary transitions
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
                // Expand range if the selected date is outside current window
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

    /// Chevron button at the left edge that loads more past dates
    private func loadMoreButton(proxy: ScrollViewProxy) -> some View {
        Button {
            let oldEarliest = dates.first
            withAnimation(.easeInOut(duration: 0.2)) {
                daysToShow += pageSize
            }
            // Keep scroll position stable by scrolling to previous earliest
            if let anchor = oldEarliest {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    proxy.scrollTo(anchor.startOfDay, anchor: .leading)
                }
            }
        } label: {
            Image(systemName: "chevron.left.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 52)
        }
        .buttonStyle(.plain)
    }

    /// True when the chip at `index` is the first day of a new month (or the very first chip)
    private func isMonthBoundary(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let calendar = Calendar.current
        return calendar.component(.month, from: dates[index]) != calendar.component(.month, from: dates[index - 1])
    }

    /// Compact month label pill shown at month boundaries
    private func monthLabel(for date: Date) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        let label = formatter.string(from: date).uppercased()
        return Text(label)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(-90))
            .frame(width: 16, height: 52)
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
