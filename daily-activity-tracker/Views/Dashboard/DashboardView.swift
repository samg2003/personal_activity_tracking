import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Activity.sortOrder) private var allActivities: [Activity]
    @Query(sort: \ActivityLog.date, order: .reverse) private var allLogs: [ActivityLog]
    @Query private var vacationDays: [VacationDay]

    @State private var showAddActivity = false

    private let scheduleEngine = ScheduleEngine()

    // MARK: - Derived Data

    private var today: Date { Date() }

    private var todayActivities: [Activity] {
        scheduleEngine.activitiesForToday(from: allActivities, on: today, vacationDays: vacationDays)
    }

    private var todayLogs: [ActivityLog] {
        allLogs.filter { $0.date.isSameDay(as: today) }
    }

    private var pendingAllDay: [Activity] {
        todayActivities.filter { activity in
            (activity.timeWindow?.slot == .allDay || activity.timeWindow == nil) &&
            !isCompleted(activity) && !isSkipped(activity)
        }
    }

    private var pendingTimed: [Activity] {
        todayActivities.filter { activity in
            activity.schedule.type != .sticky &&
            activity.timeWindow?.slot != .allDay &&
            activity.timeWindow != nil &&
            !isCompleted(activity) && !isSkipped(activity)
        }
    }

    private var stickyPending: [Activity] {
        todayActivities.filter { activity in
            activity.schedule.type == .sticky && !isCompleted(activity) && !isSkipped(activity)
        }
    }

    private var completed: [Activity] {
        todayActivities.filter { isCompleted($0) }
    }

    private var completionFraction: Double {
        let countable = todayActivities.filter { !isSkipped($0) }
        guard !countable.isEmpty else { return 1.0 }
        return Double(countable.filter { isCompleted($0) }.count) / Double(countable.count)
    }

    /// Group pending timed activities by their time slot
    private var groupedBySlot: [(slot: TimeSlot, activities: [Activity])] {
        let grouped = Dictionary(grouping: pendingTimed) { $0.timeWindow?.slot ?? .morning }
        return [TimeSlot.morning, .afternoon, .evening].compactMap { slot in
            guard let acts = grouped[slot], !acts.isEmpty else { return nil }
            return (slot, acts)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    allDaySection
                    timeBucketSections
                    backlogSection
                    completedSection
                }
                .padding()
            }
            .background(Color(.systemBackground))
            .navigationTitle(today.shortDisplay)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddActivity = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAddActivity) {
                AddActivityView()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 8) {
            ProgressRingView(progress: completionFraction)
                .frame(height: 110)

            if todayActivities.isEmpty {
                Text("No activities for today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var allDaySection: some View {
        if !pendingAllDay.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("ALL DAY")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                    ForEach(pendingAllDay) { activity in
                        ActivityRowView(
                            activity: activity,
                            isCompleted: false,
                            isSkipped: false,
                            onComplete: { toggleComplete(activity) },
                            onSkip: { reason in skipActivity(activity, reason: reason) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var timeBucketSections: some View {
        ForEach(groupedBySlot, id: \.slot) { group in
            TimeBucketSection(
                slot: group.slot,
                activities: group.activities,
                isAutoCollapsed: shouldAutoCollapse(group.slot),
                isCompleted: { isCompleted($0) },
                isSkipped: { isSkipped($0) },
                onComplete: { toggleComplete($0) },
                onSkip: { activity, reason in skipActivity(activity, reason: reason) }
            )
        }
    }

    @ViewBuilder
    private var backlogSection: some View {
        if !stickyPending.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("BACKLOG")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                ForEach(stickyPending) { activity in
                    ActivityRowView(
                        activity: activity,
                        isCompleted: false,
                        isSkipped: false,
                        onComplete: { toggleComplete(activity) },
                        onSkip: { reason in skipActivity(activity, reason: reason) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var completedSection: some View {
        if !completed.isEmpty {
            DisclosureGroup {
                ForEach(completed) { activity in
                    ActivityRowView(
                        activity: activity,
                        isCompleted: true,
                        isSkipped: false,
                        onComplete: { toggleComplete(activity) },
                        onSkip: { _ in }
                    )
                }
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("COMPLETED")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("(\(completed.count))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .tint(.secondary)
        }
    }

    // MARK: - Helpers

    private func isCompleted(_ activity: Activity) -> Bool {
        todayLogs.contains {
            $0.activity?.id == activity.id && $0.status == .completed
        }
    }

    private func isSkipped(_ activity: Activity) -> Bool {
        todayLogs.contains {
            $0.activity?.id == activity.id && $0.status == .skipped
        }
    }

    private func toggleComplete(_ activity: Activity) {
        if let log = todayLogs.first(where: { $0.activity?.id == activity.id && $0.status == .completed }) {
            modelContext.delete(log)
        } else {
            let log = ActivityLog(activity: activity, date: today, status: .completed)
            modelContext.insert(log)
        }
        try? modelContext.save()
    }

    private func skipActivity(_ activity: Activity, reason: String) {
        guard !isSkipped(activity) && !isCompleted(activity) else { return }
        let log = ActivityLog(activity: activity, date: today, status: .skipped)
        log.skipReason = reason
        modelContext.insert(log)
        try? modelContext.save()
    }

    private func shouldAutoCollapse(_ slot: TimeSlot) -> Bool {
        let hour = today.currentHour
        return hour < slot.startHour
    }
}
