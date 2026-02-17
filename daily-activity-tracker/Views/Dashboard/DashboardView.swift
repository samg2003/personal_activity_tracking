import SwiftUI
import SwiftData
import HealthKit

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Activity.sortOrder) private var allActivities: [Activity]
    @Query(sort: \ActivityLog.date, order: .reverse) private var allLogs: [ActivityLog]

    @Query private var vacationDays: [VacationDay]
    @Environment(\.scenePhase) private var scenePhase

    @State private var showAddActivity = false
    @State private var selectedDate = Date().startOfDay
    @State private var showVacationSheet = false
    @State private var showSettings = false // New state
    @State private var showUndoToast = false
    @State private var undoMessage = ""
    @State private var undoAction: () -> Void = {}
    
    @State private var editingActivity: Activity?
    
    // Quick-add (FAB) state
    @State private var quickAddActivity: Activity?
    @State private var quickAddText = ""
    @State private var showQuickAdd = false
    
    // Cumulative log sheet state
    @State private var logSheetActivity: Activity?
    
    // Photo prompt state
    @State private var photoPromptActivity: Activity?
    @State private var photoPromptLog: ActivityLog?
    @State private var completedExpanded = false


    private let scheduleEngine: ScheduleEngineProtocol = ScheduleEngine()

    // MARK: - Derived Data

    private var today: Date { selectedDate }

    private var activityStatus: ActivityStatusService {
        ActivityStatusService(
            date: today,
            todayLogs: todayLogs,
            allLogs: allLogs,
            allActivities: allActivities,
            vacationDays: vacationDays,
            scheduleEngine: scheduleEngine
        )
    }

    private var todayActivities: [Activity] {
        scheduleEngine.activitiesForToday(from: allActivities, on: today, vacationDays: vacationDays, logs: allLogs)
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
        todayActivities.filter { activity in
            if activity.type == .container {
                // Include container if ANY child has a completed session
                return containerApplicableChildren(activity).contains { child in
                    if child.isMultiSession {
                        return child.timeSlots.contains(where: { isSessionCompleted(child, slot: $0) })
                    }
                    return isFullyCompleted(child)
                }
            }
            if activity.isMultiSession {
                return activity.timeSlots.contains(where: { isSessionCompleted(activity, slot: $0) })
            }
            return isFullyCompleted(activity)
        }
    }

    /// All container children applicable today: scheduled + carry-forward
    private func containerApplicableChildren(_ container: Activity) -> [Activity] {
        scheduleEngine.applicableChildren(for: container, on: today, allActivities: allActivities, logs: allLogs)
    }

    private var skippedActivities: [Activity] {
        todayActivities.filter { activity in
            if activity.type == .container {
                // Include container if ANY child has a skipped session (and not completed)
                return containerApplicableChildren(activity).contains { child in
                    if child.isMultiSession {
                        return child.timeSlots.contains(where: { isSessionSkipped(child, slot: $0) && !isSessionCompleted(child, slot: $0) })
                    }
                    return isSkipped(child) && !isFullyCompleted(child)
                }
            }
            if activity.isMultiSession {
                return activity.timeSlots.contains(where: { isSessionSkipped(activity, slot: $0) && !isSessionCompleted(activity, slot: $0) })
            }
            return isSkipped(activity) && !isFullyCompleted(activity)
        }
    }

    private var completionFraction: Double {
        let goalsOnly = todayActivities.filter { $0.schedule.type != .sticky && $0.schedule.type != .adhoc }
        return activityStatus.completionFraction(for: goalsOnly)
    }

    private var groupedBySlot: [(slot: TimeSlot, activities: [Activity])] {
        var slotMap: [TimeSlot: [Activity]] = [:]
        for activity in pendingTimed {
            if activity.type == .container {
                // Expand container to each slot where it has pending children
                let children = containerApplicableChildren(activity)
                for slot in [TimeSlot.allDay, .morning, .afternoon, .evening] {
                    let hasPendingChildInSlot = children.contains { child in
                        let inSlot: Bool
                        if child.isMultiSession {
                            // For carry-forward children, only count overdue slots
                            if let cfSlots = scheduleEngine.carriedForwardSlots(for: child, on: today, logs: allLogs) {
                                inSlot = cfSlots.slots.contains(slot)
                            } else {
                                inSlot = child.timeSlots.contains(slot)
                            }
                        } else {
                            inSlot = (child.timeWindow?.slot ?? .morning) == slot
                        }
                        // Only count if child has a pending session in this slot
                        guard inSlot else { return false }
                        if child.isMultiSession {
                            return !isSessionCompleted(child, slot: slot) && !isSessionSkipped(child, slot: slot)
                        }
                        return !isFullyCompleted(child) && !isSkipped(child)
                    }
                    if hasPendingChildInSlot {
                        slotMap[slot, default: []].append(activity)
                    }
                }
            } else if activity.isMultiSession {
                // For carry-forward, only show overdue slots
                let slotsToCheck: [TimeSlot]
                if let cfSlots = scheduleEngine.carriedForwardSlots(for: activity, on: today, logs: allLogs) {
                    slotsToCheck = cfSlots.slots
                } else {
                    slotsToCheck = activity.timeSlots
                }
                for slot in slotsToCheck {
                    if !isSessionCompleted(activity, slot: slot)
                        && !isSessionSkipped(activity, slot: slot) {
                        slotMap[slot, default: []].append(activity)
                    }
                }
            } else {
                let slot = activity.timeWindow?.slot ?? .morning
                slotMap[slot, default: []].append(activity)
            }
        }
        return [TimeSlot.allDay, .morning, .afternoon, .evening].compactMap { slot in
            guard let acts = slotMap[slot], !acts.isEmpty else { return nil }
            return (slot, acts)
        }
    }

    private var isSelectedDateVacation: Bool {
        vacationDays.contains { $0.date.isSameDay(as: selectedDate) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // ... [VStack content] ...
                VStack(spacing: 24) {
                    DatePickerBar(
                        selectedDate: $selectedDate,
                        vacationDays: vacationDays,
                        allLogs: allLogs,
                        allActivities: allActivities,
                        scheduleEngine: scheduleEngine
                    )
                    
                    // Vacation banner (informational only, no standalone button)
                    if isSelectedDateVacation {
                        HStack {
                            Image(systemName: "airplane")
                                .foregroundStyle(.blue)
                            Text("Vacation Day")
                                .font(.subheadline.bold())
                            Spacer()
                            Button("Remove") {
                                toggleVacation(for: selectedDate, isVacation: false)
                            }
                            .font(.caption)
                            .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    headerSection
                    allDaySection
                    timeBucketSections
                    backlogSection
                    completedSection
                    skippedSection
                }
                .padding()
            }
            .background(Color(.systemBackground))
            .onChange(of: allLogs.count) {
                if allDone { completedExpanded = true }
            }
            .onChange(of: selectedDate) {
                completedExpanded = allDone
            }
            .navigationTitle(selectedDate.isSameDay(as: Date()) ? "Today" : selectedDate.shortDisplay)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack {
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.body)
                        }
                        Button { showVacationSheet = true } label: {
                            Image(systemName: "airplane")
                                .font(.body)
                        }
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
                AddActivityView(activityToEdit: nil)
            }
            .sheet(item: $editingActivity) { activity in
                AddActivityView(activityToEdit: activity)
            }
            .sheet(isPresented: $showVacationSheet) {
                VacationModeSheet(selectedDate: selectedDate)
            }
            .sheet(item: $logSheetActivity) { activity in
                CumulativeLogSheet(activity: activity, date: today)
            }
            .sheet(item: $photoPromptActivity) { activity in
                NavigationStack {
                    CameraView(
                        activityID: activity.id,
                        activityName: activity.name,
                        slots: activity.photoSlots
                    ) { slotImages in
                        let date = today
                        var filenames: [String: String] = [:]
                        for (slot, image) in slotImages {
                            if let filename = MediaService.shared.savePhoto(image, activityID: activity.id, date: date, slot: slot) {
                                filenames[slot] = filename
                            }
                        }
                        if let log = photoPromptLog {
                            log.photoFilenames = filenames
                            // Legacy compat: set photoFilename to first captured slot
                            log.photoFilename = filenames.values.first
                        }
                        photoPromptActivity = nil
                        photoPromptLog = nil
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Skip Photo") {
                                photoPromptActivity = nil
                                photoPromptLog = nil
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .undoToast(isPresented: $showUndoToast, message: undoMessage, onUndo: undoAction)
            .overlay(alignment: .bottomTrailing) {
                floatingActionButton
            }
            .onAppear { syncHealthKit() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { syncHealthKit() }
            }
        }
    }

    // MARK: - FAB
    
    @ViewBuilder
    private var floatingActionButton: some View {
        let cumulative = todayActivities.filter { $0.type == .cumulative }
        if !cumulative.isEmpty {
            Menu {
                ForEach(cumulative) { activity in
                    Button {
                        quickAddActivity = activity
                        quickAddText = ""
                        showQuickAdd = true
                    } label: {
                        Label("Add to \(activity.name)", systemImage: activity.icon)
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.accentColor)
                    .clipShape(Circle())
                    .shadow(radius: 4, y: 4)
            }
            .padding()
            .alert("Add to \(quickAddActivity?.name ?? "")", isPresented: $showQuickAdd) {
                TextField(quickAddActivity?.unit ?? "Amount", text: $quickAddText)
                    .keyboardType(.decimalPad)
                Button("Add") {
                    if let activity = quickAddActivity, let val = Double(quickAddText), val > 0 {
                        addCumulativeLog(activity, value: val)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let target = quickAddActivity?.targetValue {
                    Text("Current: \(formatQuickAddCurrent()) / \(Int(target)) \(quickAddActivity?.unit ?? "")")
                }
            }
        }
    }

    private func formatQuickAddCurrent() -> String {
        guard let activity = quickAddActivity else { return "0" }
        let total = cumulativeValue(for: activity)
        return total.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", total) : String(format: "%.1f", total)
    }

    // MARK: - Sections

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 8) {
            ProgressRingView(progress: completionFraction)

            if todayActivities.isEmpty {
                Text("No activities for today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var allDaySection: some View {
        AllDaySection(
            activities: allDayActivities,
            cumulativeValues: { cumulativeValue(for: $0) },
            onAdd: { activity, value in addCumulativeLog(activity, value: value) },
            isSkipped: { isSkipped($0) },
            onSkip: { activity, reason in skipActivity(activity, reason: reason) },
            onShowLogs: { activity in logSheetActivity = activity }
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
                    activityView(for: activity, inSlot: group.slot)
                }
            }
        }
    }

    @ViewBuilder
    private var backlogSection: some View {
        if !stickyPending.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("REMINDERS")
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

    private var allDone: Bool {
        pendingTimed.isEmpty && !completed.isEmpty
    }

    @ViewBuilder
    private var completedSection: some View {
        if !completed.isEmpty {
            DisclosureGroup(isExpanded: $completedExpanded) {
                ForEach(groupedCompletedBySlot, id: \.slot) { group in
                    // Slot header within completed
                    HStack(spacing: 4) {
                        Image(systemName: group.slot.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.6))
                        Text(group.slot.displayName.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.6))
                        Spacer()
                    }
                    .padding(.top, 4)

                    ForEach(group.items, id: \.id) { item in
                        activityView(for: item.activity, inSlot: item.slot, containerDisplayMode: .completedOnly)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("COMPLETED")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("(\(completedItemCount))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if allDone {
                        Spacer()
                        Text("All done! 🎉")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            .tint(.secondary)
        }
    }

    /// Completed items grouped by time bucket
    private var groupedCompletedBySlot: [(slot: TimeSlot, items: [(id: String, activity: Activity, slot: TimeSlot?)])] {
        var slotMap: [TimeSlot: [(id: String, activity: Activity, slot: TimeSlot?)]] = [:]
        for activity in completed {
            if activity.isMultiSession {
                for slot in activity.timeSlots where isSessionCompleted(activity, slot: slot) {
                    slotMap[slot, default: []].append(("\(activity.id)-\(slot.rawValue)", activity, slot))
                }
            } else if activity.type == .container {
                // Containers go into each slot where they have completed children
                let children = containerApplicableChildren(activity)
                for slot in [TimeSlot.allDay, .morning, .afternoon, .evening] {
                    let hasCompletedChild = children.contains { child in
                        if child.isMultiSession {
                            return child.timeSlots.contains(slot) && isSessionCompleted(child, slot: slot)
                        }
                        return (child.timeWindow?.slot ?? .morning) == slot && isFullyCompleted(child)
                    }
                    if hasCompletedChild {
                        slotMap[slot, default: []].append(("\(activity.id)-\(slot.rawValue)", activity, slot))
                    }
                }
            } else {
                let slot = activity.timeWindow?.slot ?? .morning
                slotMap[slot, default: []].append((activity.id.uuidString, activity, nil))
            }
        }
        return [TimeSlot.allDay, .morning, .afternoon, .evening].compactMap { slot in
            guard let items = slotMap[slot], !items.isEmpty else { return nil }
            return (slot, items)
        }
    }

    /// Total completed items including individual multi-session slots
    private var completedItemCount: Int {
        completed.reduce(0) { count, activity in
            if activity.type == .container {
                // Count individual completed sessions/children
                return count + containerApplicableChildren(activity).reduce(0) { childCount, child in
                    if child.isMultiSession {
                        return childCount + child.timeSlots.filter { isSessionCompleted(child, slot: $0) }.count
                    }
                    return childCount + (isFullyCompleted(child) ? 1 : 0)
                }
            }
            if activity.isMultiSession {
                return count + activity.timeSlots.filter { isSessionCompleted(activity, slot: $0) }.count
            }
            return count + 1
        }
    }

    @ViewBuilder
    private var skippedSection: some View {
        if !skippedActivities.isEmpty {
            DisclosureGroup {
                ForEach(groupedSkippedBySlot, id: \.slot) { group in
                    // Slot header within skipped
                    HStack(spacing: 4) {
                        Image(systemName: group.slot.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.6))
                        Text(group.slot.displayName.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.6))
                        Spacer()
                    }
                    .padding(.top, 4)

                    ForEach(group.items, id: \.id) { item in
                        if item.activity.type == .container {
                            activityView(for: item.activity, inSlot: item.slot, containerDisplayMode: .skippedOnly)
                        } else {
                            skippedRow(activity: item.activity, slotLabel: item.activity.isMultiSession ? item.displaySlot : nil) {
                                if let slot = item.slot {
                                    unskipSession(item.activity, slot: slot)
                                } else {
                                    unskipActivity(item.activity)
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "forward.fill")
                        .foregroundStyle(.orange)
                    Text("SKIPPED")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("(\(skippedItemCount))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .tint(.secondary)
        }
    }

    private var groupedSkippedBySlot: [(slot: TimeSlot, items: [(id: String, activity: Activity, slot: TimeSlot?, displaySlot: String?)])] {
        var slotMap: [TimeSlot: [(id: String, activity: Activity, slot: TimeSlot?, displaySlot: String?)]] = [:]
        for activity in skippedActivities {
            if activity.isMultiSession {
                for slot in skippedSlots(for: activity) {
                    slotMap[slot, default: []].append(("\(activity.id)-\(slot.rawValue)", activity, slot, slot.displayName))
                }
            } else if activity.type == .container {
                // Containers go into each slot where they have skipped children
                let children = containerApplicableChildren(activity)
                for slot in [TimeSlot.allDay, .morning, .afternoon, .evening] {
                    let hasSkippedChild = children.contains { child in
                        if child.isMultiSession {
                            return child.timeSlots.contains(slot) && isSessionSkipped(child, slot: slot) && !isSessionCompleted(child, slot: slot)
                        }
                        return (child.timeWindow?.slot ?? .morning) == slot && isSkipped(child) && !isFullyCompleted(child)
                    }
                    if hasSkippedChild {
                        slotMap[slot, default: []].append(("\(activity.id)-\(slot.rawValue)", activity, slot, slot.displayName))
                    }
                }
            } else {
                let slot = activity.timeWindow?.slot ?? .morning
                slotMap[slot, default: []].append((activity.id.uuidString, activity, nil, nil))
            }
        }
        return [TimeSlot.allDay, .morning, .afternoon, .evening].compactMap { slot in
            guard let items = slotMap[slot], !items.isEmpty else { return nil }
            return (slot, items)
        }
    }

    @ViewBuilder
    private func skippedRow(activity: Activity, slotLabel: String?, onUnskip: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "forward.fill")
                .font(.system(size: 14))
                .foregroundStyle(.orange)

            Image(systemName: activity.icon)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: activity.hexColor).opacity(0.5))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(activity.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .strikethrough(true, color: .secondary)
                if let slot = slotLabel {
                    Text(slot)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let reason = skipReason(for: activity) {
                Text(reason)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }

            Spacer()

            Button {
                onUnskip()
            } label: {
                Text("Unskip")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Skipped slots for a multi-session activity (sessions that are skipped and not completed)
    private func skippedSlots(for activity: Activity) -> [TimeSlot] {
        activityStatus.skippedSlots(for: activity)
    }

    /// Total skipped items including individual multi-session slots
    private var skippedItemCount: Int {
        skippedActivities.reduce(0) { count, activity in
            if activity.type == .container {
                return count + containerApplicableChildren(activity).reduce(0) { childCount, child in
                    if child.isMultiSession {
                        return childCount + child.timeSlots.filter { isSessionSkipped(child, slot: $0) && !isSessionCompleted(child, slot: $0) }.count
                    }
                    return childCount + (isSkipped(child) && !isFullyCompleted(child) ? 1 : 0)
                }
            }
            if activity.isMultiSession {
                return count + skippedSlots(for: activity).count
            }
            return count + 1
        }
    }

    /// Unskip a single session of a multi-session activity
    private func unskipSession(_ activity: Activity, slot: TimeSlot) {
        guard let skipLog = todayLogs.first(where: {
            $0.activity?.id == activity.id && $0.status == .skipped && $0.timeSlot == slot
        }) else { return }
        modelContext.delete(skipLog)
    }

    // MARK: - Type-Dispatched Row

    /// Default rendering (no slot context) — used by backlog, completed, skipped sections
    @ViewBuilder
    private func activityView(for activity: Activity) -> some View {
        activityView(for: activity, inSlot: nil)
    }

    /// Slot-aware rendering for time bucket sections
    @ViewBuilder
    private func activityView(for activity: Activity, inSlot slot: TimeSlot?, containerDisplayMode: ContainerDisplayMode = .full) -> some View {
        Group {
            switch activity.type {
            case .checkbox, .metric:
                if activity.isMultiSession, let slot {
                    ActivityRowView(
                        activity: activity,
                        isCompleted: isSessionCompleted(activity, slot: slot),
                        isSkipped: isSessionSkipped(activity, slot: slot),
                        onComplete: { completeCheckbox(activity, slot: slot) },
                        onSkip: { reason in skipActivity(activity, reason: reason, slot: slot) }
                    )
                } else {
                    ActivityRowView(
                        activity: activity,
                        isCompleted: isFullyCompleted(activity),
                        isSkipped: isSkipped(activity),
                        onComplete: { completeCheckbox(activity) },
                        onSkip: { reason in skipActivity(activity, reason: reason) }
                    )
                }
            case .value:
                if activity.isMultiSession, let slot {
                    ValueInputRow(
                        activity: activity,
                        currentValue: latestValue(for: activity, slot: slot),
                        onLog: { value in logValue(activity, value: value, slot: slot) },
                        onSkip: { reason in skipActivity(activity, reason: reason, slot: slot) },
                        onRemove: { removeValueLog(activity, slot: slot) },
                        onTakePhoto: nil
                    )
                } else {
                    ValueInputRow(
                        activity: activity,
                        currentValue: latestValue(for: activity),
                        onLog: { value in logValue(activity, value: value) },
                        onSkip: { reason in skipActivity(activity, reason: reason) },
                        onRemove: { removeValueLog(activity) },
                        onTakePhoto: nil
                    )
                }
            case .cumulative:
                ValueInputRow(
                    activity: activity,
                    currentValue: cumulativeValue(for: activity),
                    onLog: { value in addCumulativeLog(activity, value: value) },
                    onSkip: { reason in skipActivity(activity, reason: reason) },
                    onShowLogs: { logSheetActivity = activity }
                )
            case .container:
                ContainerRowView(
                    activity: activity,
                    todayLogs: todayLogs,
                    allLogs: allLogs,
                    scheduleEngine: scheduleEngine,
                    today: today,
                    allActivities: allActivities,
                    onCompleteChild: { child, childSlot in completeCheckbox(child, slot: childSlot) },
                    onSkipChild: { child, reason, childSlot in skipActivity(child, reason: reason, slot: childSlot) },
                    onUnskipChild: { child, childSlot in
                        if let childSlot {
                            unskipSession(child, slot: childSlot)
                        } else {
                            unskipActivity(child)
                        }
                    },
                    slotFilter: slot,
                    displayMode: containerDisplayMode
                )
            }
        }
        .background(
            carriedForwardOriginalDate(activity) != nil && !isFullyCompleted(activity) && !isSkipped(activity)
                ? Color.red.opacity(0.08)
                : Color.clear
        )
        .overlay(alignment: .topTrailing) {
            if let dueDate = carriedForwardOriginalDate(activity),
               !isFullyCompleted(activity), !isSkipped(activity) {
                Text("⏳ Due from \(dueDate.shortMonthDay)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.15))
                    .clipShape(Capsule())
                    .offset(y: -2)
            }
        }
    }

    private func carriedForwardOriginalDate(_ activity: Activity) -> Date? {
        scheduleEngine.carriedForwardDate(for: activity, on: today, logs: allLogs)
    }

    /// Date to use when creating a log — original carry-forward date if applicable, otherwise today
    private func effectiveLogDate(for activity: Activity) -> Date {
        carriedForwardOriginalDate(activity) ?? today
    }

    /// Find logs for an activity on its effective date (handles carry-forwarded items)
    private func effectiveLogs(for activity: Activity) -> [ActivityLog] {
        let logDate = effectiveLogDate(for: activity)
        return allLogs.filter { $0.activity?.id == activity.id && $0.date.isSameDay(as: logDate) }
    }

    // MARK: - Completion Logic (delegates to ActivityStatusService)

    private func isFullyCompleted(_ activity: Activity) -> Bool {
        activityStatus.isFullyCompleted(activity)
    }

    private func isSkipped(_ activity: Activity) -> Bool {
        activityStatus.isSkipped(activity)
    }

    // MARK: - Session-Level Checks (multi-session)

    private func isSessionCompleted(_ activity: Activity, slot: TimeSlot) -> Bool {
        activityStatus.isSessionCompleted(activity, slot: slot)
    }

    private func isSessionSkipped(_ activity: Activity, slot: TimeSlot) -> Bool {
        activityStatus.isSessionSkipped(activity, slot: slot)
    }

    /// Checks whether a photo prompt should be triggered (only for photo-metric activities)
    private func isPhotoDue(for activity: Activity) -> Bool {
        return activity.type == .metric && activity.metricKind == .photo
    }

    /// Trigger photo capture sheet, optionally attaching to a specific log
    private func triggerPhotoPrompt(for activity: Activity, log: ActivityLog? = nil) {
        let targetLog = log ?? todayLogs.first(where: {
            $0.activity?.id == activity.id && $0.status == .completed
        })
        photoPromptLog = targetLog
        photoPromptActivity = activity
    }

    private func completeCheckbox(_ activity: Activity, slot: TimeSlot? = nil) {
        // For multi-session with a slot, toggle that specific session
        let logDate = effectiveLogDate(for: activity)
        if let slot, activity.isMultiSession {
            if isSessionCompleted(activity, slot: slot) {
                // Uncomplete this session
                if let log = effectiveLogs(for: activity).first(where: {
                    $0.status == .completed && $0.timeSlot == slot
                }) {
                    modelContext.delete(log)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showUndo("Uncompleted \(activity.name) (\(slot.displayName))") {
                        let restored = ActivityLog(activity: activity, date: logDate, status: .completed)
                        restored.timeSlotRaw = slot.rawValue
                        modelContext.insert(restored)
                    }
                }
                return
            }
            let log = ActivityLog(activity: activity, date: logDate, status: .completed)
            log.timeSlotRaw = slot.rawValue
            modelContext.insert(log)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            if isPhotoDue(for: activity) {
                triggerPhotoPrompt(for: activity, log: log)
            }
            showUndo("Completed \(activity.name) (\(slot.displayName))") { [log] in
                modelContext.delete(log)
            }
            return
        }

        // Single-session (original logic)
        if isFullyCompleted(activity) {
            if let log = effectiveLogs(for: activity).first(where: { $0.status == .completed }) {
                modelContext.delete(log)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showUndo("Uncompleted \(activity.name)") {
                    let restored = ActivityLog(activity: activity, date: logDate, status: .completed)
                    modelContext.insert(restored)
                }
            }
            return
        }
        
        let log = ActivityLog(activity: activity, date: logDate, status: .completed)
        modelContext.insert(log)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        writeToHealthKit(activity: activity, value: 1.0)
        
        if isPhotoDue(for: activity) {
            triggerPhotoPrompt(for: activity, log: log)
        }
        
        showUndo("Completed \(activity.name)") { [log] in
            modelContext.delete(log)
        }
    }

    private func logValue(_ activity: Activity, value: Double, slot: TimeSlot? = nil) {
        let logDate = effectiveLogDate(for: activity)
        if let slot, activity.isMultiSession {
            // Multi-session: find existing log for this specific slot
            if let existing = effectiveLogs(for: activity).first(where: {
                $0.status == .completed && $0.timeSlot == slot
            }) {
                modelContext.delete(existing)
            }
            let log = ActivityLog(activity: activity, date: logDate, status: .completed, value: value)
            log.timeSlotRaw = slot.rawValue
            modelContext.insert(log)
            writeToHealthKit(activity: activity, value: value)
            if isPhotoDue(for: activity) {
                photoPromptLog = log
                photoPromptActivity = activity
            }
            return
        }
        if let existing = effectiveLogs(for: activity).first(where: { $0.status == .completed }) {
            modelContext.delete(existing)
        }
        let log = ActivityLog(activity: activity, date: logDate, status: .completed, value: value)
        modelContext.insert(log)
        
        // Integrations
        writeToHealthKit(activity: activity, value: value)

        // Photo cadence check for value activities
        if isPhotoDue(for: activity) {
            photoPromptLog = log
            photoPromptActivity = activity
        }
    }

    private func addCumulativeLog(_ activity: Activity, value: Double) {
        let logDate = effectiveLogDate(for: activity)
        let log = ActivityLog(activity: activity, date: logDate, status: .completed, value: value)
        modelContext.insert(log)
        
        writeToHealthKit(activity: activity, value: value)
        
        showUndo("Added \(Int(value)) to \(activity.name)") { [log] in
            modelContext.delete(log)
        }
    }

    private func removeValueLog(_ activity: Activity, slot: TimeSlot? = nil) {
        let logs = effectiveLogs(for: activity)
        let matchLog: ActivityLog?
        if let slot, activity.isMultiSession {
            matchLog = logs.first(where: {
                $0.status == .completed && $0.timeSlot == slot
            })
        } else {
            matchLog = logs.first(where: { $0.status == .completed })
        }
        guard let log = matchLog else { return }
        let oldValue = log.value
        let oldSlotRaw = log.timeSlotRaw
        let logDate = log.date
        modelContext.delete(log)
        
        showUndo("Cleared \(activity.name)") {
            let restored = ActivityLog(activity: activity, date: logDate, status: .completed, value: oldValue)
            restored.timeSlotRaw = oldSlotRaw
            modelContext.insert(restored)
        }
    }

    private func removeLastCumulativeLog(_ activity: Activity) {
        guard let lastLog = effectiveLogs(for: activity).last(where: { $0.status == .completed }) else { return }
        let oldValue = lastLog.value
        let logDate = lastLog.date
        modelContext.delete(lastLog)
        
        showUndo("Removed entry from \(activity.name)") {
            let restored = ActivityLog(activity: activity, date: logDate, status: .completed, value: oldValue)
            modelContext.insert(restored)
        }
    }

    private func toggleVacation(for date: Date, isVacation: Bool) {
        if isVacation {
            guard !vacationDays.contains(where: { $0.date.isSameDay(as: date) }) else { return }
            let vacation = VacationDay(date: date.startOfDay)
            modelContext.insert(vacation)
            createVacationSkipLogs(for: date)
        } else {
            if let existing = vacationDays.first(where: { $0.date.isSameDay(as: date) }) {
                modelContext.delete(existing)
            }
            removeVacationSkipLogs(for: date)
        }
    }

    /// Auto-skip all scheduled activities on a vacation day
    private func createVacationSkipLogs(for date: Date) {
        let scheduled = scheduleEngine.activitiesForToday(from: allActivities, on: date, vacationDays: [])
        let dateLogs = allLogs.filter { $0.date.isSameDay(as: date) }

        for activity in scheduled {
            if activity.type == .container {
                // Skip each child that isn't already completed/skipped
                for child in activity.historicalChildren(on: date, from: allActivities) {
                    let alreadyHandled = dateLogs.contains {
                        $0.activity?.id == child.id && ($0.status == .completed || $0.status == .skipped)
                    }
                    guard !alreadyHandled else { continue }
                    let log = ActivityLog(activity: child, date: date.startOfDay, status: .skipped)
                    log.skipReason = "Vacation"
                    modelContext.insert(log)
                }
            } else {
                if activity.isMultiSession {
                    for slot in activity.timeSlots {
                        let alreadyHandled = dateLogs.contains {
                            $0.activity?.id == activity.id &&
                            ($0.status == .completed || $0.status == .skipped) &&
                            $0.timeSlot == slot
                        }
                        guard !alreadyHandled else { continue }
                        let log = ActivityLog(activity: activity, date: date.startOfDay, status: .skipped)
                        log.skipReason = "Vacation"
                        log.timeSlotRaw = slot.rawValue
                        modelContext.insert(log)
                    }
                } else {
                    let alreadyHandled = dateLogs.contains {
                        $0.activity?.id == activity.id && ($0.status == .completed || $0.status == .skipped)
                    }
                    guard !alreadyHandled else { continue }
                    let log = ActivityLog(activity: activity, date: date.startOfDay, status: .skipped)
                    log.skipReason = "Vacation"
                    modelContext.insert(log)
                }
            }
        }
    }

    /// Remove all vacation-reason skip logs when vacation is undone
    private func removeVacationSkipLogs(for date: Date) {
        let vacationLogs = allLogs.filter {
            $0.date.isSameDay(as: date) && $0.status == .skipped && $0.skipReason == "Vacation"
        }
        for log in vacationLogs {
            modelContext.delete(log)
        }
    }

    private func skipActivity(_ activity: Activity, reason: String, slot: TimeSlot? = nil) {
        // For multi-session with a slot, skip that specific session
        if let slot, activity.isMultiSession {
            guard !isSessionSkipped(activity, slot: slot) && !isSessionCompleted(activity, slot: slot) else { return }
            let logDate = effectiveLogDate(for: activity)
            let log = ActivityLog(activity: activity, date: logDate, status: .skipped)
            log.skipReason = reason
            log.timeSlotRaw = slot.rawValue
            modelContext.insert(log)
            showUndo("Skipped \(activity.name) (\(slot.displayName))") { [log] in
                modelContext.delete(log)
            }
            return
        }

        guard !isSkipped(activity) && !isFullyCompleted(activity) else { return }
        let logDate = effectiveLogDate(for: activity)
        let log = ActivityLog(activity: activity, date: logDate, status: .skipped)
        log.skipReason = reason
        modelContext.insert(log)        
        showUndo("Skipped \(activity.name)") { [log] in
            modelContext.delete(log)
        }
    }

    private func unskipActivity(_ activity: Activity) {
        if activity.type == .container {
            let applicable = containerApplicableChildren(activity)
            for child in applicable {
                if let skipLog = todayLogs.first(where: {
                    $0.activity?.id == child.id && $0.status == .skipped
                }) {
                    modelContext.delete(skipLog)
                }
            }
            return
        }
        if activity.isMultiSession {
            // Delete all slot-specific skip logs
            let skipLogs = todayLogs.filter {
                $0.activity?.id == activity.id && $0.status == .skipped
            }
            for log in skipLogs { modelContext.delete(log) }
            return
        }
        guard let skipLog = todayLogs.first(where: {
            $0.activity?.id == activity.id && $0.status == .skipped
        }) else { return }
        modelContext.delete(skipLog)
    }

    private func skipReason(for activity: Activity) -> String? {
        activityStatus.skipReason(for: activity)
    }

    private func showUndo(_ message: String, action: @escaping () -> Void) {
        undoMessage = message
        undoAction = action
        showUndoToast = true
    }

    // MARK: - Value Queries

    private func latestValue(for activity: Activity, slot: TimeSlot? = nil) -> Double? {
        activityStatus.latestValue(for: activity, slot: slot)
    }

    private func cumulativeValue(for activity: Activity) -> Double {
        activityStatus.cumulativeValue(for: activity)
    }

    private func shouldAutoCollapse(_ slot: TimeSlot) -> Bool {
        today.currentHour < slot.startHour
    }
    
    // MARK: - HealthKit Sync
    
    private func syncHealthKit() {
        guard HealthKitService.shared.isAvailable else { return }
        
        Task {
            // 1. Request Auth for all relevant types
            let typesToRead = Set(todayActivities.compactMap { $0.healthKitTypeID }.compactMap { HealthKitService.identifierFrom($0) })
            guard !typesToRead.isEmpty else { return }
            try? await HealthKitService.shared.requestAuthorization(for: typesToRead)
            
            // 2. Read and Update
            for activity in todayActivities {
                guard let typeID = activity.healthKitTypeID,
                      let hkType = HealthKitService.identifierFrom(typeID),
                      activity.healthKitMode == .read || activity.healthKitMode == .both
                else { continue }
                
                // Determine unit
                let unit: HKUnit = HealthKitService.unitFor(type: hkType)
                
                let value = try? await HealthKitService.shared.readTotalToday(for: hkType, unit: unit)
                if let val = value, val > 0 {
                    // Compare against existing HK-tagged log (not full cumulative, which includes manual entries)
                    let existingHKValue = await MainActor.run {
                        todayLogs.first {
                            $0.activity?.id == activity.id &&
                            $0.status == .completed &&
                            $0.note == "Synced from HealthKit"
                        }?.value ?? 0
                    }
                    if abs(existingHKValue - val) > 0.1 {
                        await MainActor.run {
                            // Upsert: find existing HK-tagged log and update, otherwise insert
                            let hkTaggedLog = todayLogs.first {
                                $0.activity?.id == activity.id &&
                                $0.status == .completed &&
                                $0.note == "Synced from HealthKit"
                            }
                            if let existing = hkTaggedLog {
                                existing.value = val
                            } else {
                                let log = ActivityLog(activity: activity, date: today, status: .completed, value: val)
                                log.note = "Synced from HealthKit"
                                modelContext.insert(log)
                            }
                        }
                    }
                }
            }
        }
    }

    private func writeToHealthKit(activity: Activity, value: Double) {
        guard let typeID = activity.healthKitTypeID,
              let hkType = HealthKitService.identifierFrom(typeID),
              activity.healthKitMode == .write || activity.healthKitMode == .both
        else { return }
        
        Task {
            // Simple unit mapping
            let unit: HKUnit = HealthKitService.unitFor(type: hkType)
            try? await HealthKitService.shared.writeSample(type: hkType, value: value, unit: unit, date: Date())
        }
    }
}

