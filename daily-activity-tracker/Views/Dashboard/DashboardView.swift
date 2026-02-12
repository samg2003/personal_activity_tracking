import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Activity.sortOrder) private var allActivities: [Activity]
    @Query(sort: \ActivityLog.date, order: .reverse) private var allLogs: [ActivityLog]
    @Query private var vacationDays: [VacationDay]

    @State private var showAddActivity = false
    @State private var selectedDate = Date().startOfDay
    @State private var showVacationSheet = false
    @State private var showUndoToast = false
    @State private var undoMessage = ""
    @State private var undoAction: () -> Void = {}

    private let scheduleEngine: ScheduleEngineProtocol = ScheduleEngine()

    // MARK: - Derived Data

    private var today: Date { selectedDate }

    private var todayActivities: [Activity] {
        scheduleEngine.activitiesForToday(from: allActivities, on: today, vacationDays: vacationDays)
    }

    private var todayLogs: [ActivityLog] {
        allLogs.filter { $0.date.isSameDay(as: today) }
    }

    // All Day cumulative items (outside time buckets)
    private var allDayActivities: [Activity] {
        todayActivities.filter { $0.type == .cumulative && $0.timeWindow?.slot == .allDay }
    }

    // Non-cumulative pending items in time buckets
    private var pendingTimed: [Activity] {
        todayActivities.filter { activity in
            activity.schedule.type != .sticky
            && !(activity.type == .cumulative && activity.timeWindow?.slot == .allDay)
            && !isFullyCompleted(activity)
            && !isSkipped(activity)
        }
    }

    private var stickyPending: [Activity] {
        todayActivities.filter { activity in
            activity.schedule.type == .sticky && !isFullyCompleted(activity) && !isSkipped(activity)
        }
    }

    private var completed: [Activity] {
        todayActivities.filter { isFullyCompleted($0) }
    }

    private var completionFraction: Double {
        let countable = todayActivities.filter { !isSkipped($0) }
        guard !countable.isEmpty else { return 1.0 }
        return Double(countable.filter { isFullyCompleted($0) }.count) / Double(countable.count)
    }

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
                    DatePickerBar(selectedDate: $selectedDate)
                    headerSection
                    allDaySection
                    timeBucketSections
                    backlogSection
                    completedSection
                }
                .padding()
            }
            .background(Color(.systemBackground))
            .navigationTitle(selectedDate.isSameDay(as: Date()) ? "Today" : selectedDate.shortDisplay)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showVacationSheet = true } label: {
                        Image(systemName: "airplane")
                            .font(.body)
                    }
                }
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
            .sheet(isPresented: $showVacationSheet) {
                VacationModeSheet()
            }
            .undoToast(isPresented: $showUndoToast, message: undoMessage, onUndo: undoAction)
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
        AllDaySection(
            activities: allDayActivities,
            cumulativeValues: { cumulativeTotal(for: $0) },
            onAdd: { activity, value in addCumulativeLog(activity, value: value) }
        )
    }

    @ViewBuilder
    private var timeBucketSections: some View {
        ForEach(groupedBySlot, id: \.slot) { group in
            VStack(alignment: .leading, spacing: 8) {
                // Bucket header
                Button {
                    // Collapse handled inside TimeBucketSection
                } label: {
                    HStack {
                        Image(systemName: group.slot.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(group.slot.displayName.uppercased())
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                ForEach(group.activities) { activity in
                    activityView(for: activity)
                }
            }
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
                    activityView(for: activity)
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
                        onComplete: { },
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

    // MARK: - Type-Dispatched Row

    @ViewBuilder
    private func activityView(for activity: Activity) -> some View {
        switch activity.type {
        case .checkbox:
            ActivityRowView(
                activity: activity,
                isCompleted: isFullyCompleted(activity),
                isSkipped: isSkipped(activity),
                onComplete: { completeCheckbox(activity) },
                onSkip: { reason in skipActivity(activity, reason: reason) }
            )
        case .value:
            ValueInputRow(
                activity: activity,
                currentValue: latestValue(for: activity),
                onLog: { value in logValue(activity, value: value) }
            )
        case .cumulative:
            // Non-allDay cumulative shown inline as a value-like row
            ValueInputRow(
                activity: activity,
                currentValue: cumulativeTotal(for: activity),
                onLog: { value in addCumulativeLog(activity, value: value) }
            )
        case .container:
            ContainerRowView(
                activity: activity,
                todayLogs: todayLogs,
                scheduleEngine: scheduleEngine,
                today: today,
                onCompleteChild: { child in completeCheckbox(child) },
                onSkipChild: { child, reason in skipActivity(child, reason: reason) }
            )
        }
    }

    // MARK: - Completion Logic

    private func isFullyCompleted(_ activity: Activity) -> Bool {
        switch activity.type {
        case .checkbox:
            return todayLogs.contains { $0.activity?.id == activity.id && $0.status == .completed }
        case .value:
            return todayLogs.contains { $0.activity?.id == activity.id && $0.status == .completed }
        case .cumulative:
            guard let target = activity.targetValue, target > 0 else { return false }
            return cumulativeTotal(for: activity) >= target
        case .container:
            // Container is complete if all today-applicable children are complete
            let applicable = activity.children.filter { scheduleEngine.shouldShow($0, on: today) }
            guard !applicable.isEmpty else { return true }
            return applicable.allSatisfy { isFullyCompleted($0) }
        }
    }

    private func isSkipped(_ activity: Activity) -> Bool {
        todayLogs.contains { $0.activity?.id == activity.id && $0.status == .skipped }
    }

    // MARK: - Mutations

    private func completeCheckbox(_ activity: Activity) {
        guard !isFullyCompleted(activity) else { return }
        let log = ActivityLog(activity: activity, date: today, status: .completed)
        modelContext.insert(log)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showUndo("Completed \(activity.name)") { [log] in
            modelContext.delete(log)
        }
    }

    private func logValue(_ activity: Activity, value: Double) {
        if let existing = todayLogs.first(where: { $0.activity?.id == activity.id && $0.status == .completed }) {
            modelContext.delete(existing)
        }
        let log = ActivityLog(activity: activity, date: today, status: .completed, value: value)
        modelContext.insert(log)
    }

    private func addCumulativeLog(_ activity: Activity, value: Double) {
        let log = ActivityLog(activity: activity, date: today, status: .completed, value: value)
        modelContext.insert(log)
    }

    private func skipActivity(_ activity: Activity, reason: String) {
        guard !isSkipped(activity) && !isFullyCompleted(activity) else { return }
        let log = ActivityLog(activity: activity, date: today, status: .skipped)
        log.skipReason = reason
        modelContext.insert(log)
        showUndo("Skipped \(activity.name)") { [log] in
            modelContext.delete(log)
        }
    }

    private func showUndo(_ message: String, action: @escaping () -> Void) {
        undoMessage = message
        undoAction = action
        showUndoToast = true
    }

    // MARK: - Value Queries

    private func latestValue(for activity: Activity) -> Double? {
        todayLogs.first(where: { $0.activity?.id == activity.id && $0.status == .completed })?.value
    }

    private func cumulativeTotal(for activity: Activity) -> Double {
        todayLogs
            .filter { $0.activity?.id == activity.id && $0.status == .completed }
            .reduce(0) { $0 + ($1.value ?? 0) }
    }

    private func shouldAutoCollapse(_ slot: TimeSlot) -> Bool {
        today.currentHour < slot.startHour
    }
}
