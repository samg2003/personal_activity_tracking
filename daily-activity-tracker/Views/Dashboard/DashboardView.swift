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
        todayActivities.filter { isFullyCompleted($0) }
    }

    private var skippedActivities: [Activity] {
        todayActivities.filter { isSkipped($0) && !isFullyCompleted($0) }
    }

    private var completionFraction: Double {
        var total = 0.0
        var done = 0.0
        var skippedCount = 0
        for activity in todayActivities {
            if isSkipped(activity) { skippedCount += 1; continue }
            // No-target cumulatives have no completion concept — exclude from progress
            if activity.type == .cumulative && (activity.targetValue == nil || activity.targetValue == 0) { continue }
            if activity.type == .container {
                let children = activity.historicalChildren(on: today, from: allActivities)
                    .filter { scheduleEngine.shouldShow($0, on: today) }
                let count = Double(max(children.count, 1))
                total += count
                done += Double(children.filter { isFullyCompleted($0) }.count)
            } else if activity.type == .cumulative, let target = activity.targetValue, target > 0 {
                // Partial credit for cumulative: value/target capped at 1
                total += 1.0
                done += min(cumulativeValue(for: activity) / target, 1.0)
            } else if activity.isMultiSession {
                let sessions = Double(activity.timeSlots.count)
                total += sessions
                if isFullyCompleted(activity) {
                    done += sessions
                } else {
                    for slot in activity.timeSlots {
                        if isSessionCompleted(activity, slot: slot) { done += 1.0 }
                    }
                }
            } else {
                total += 1.0
                if isFullyCompleted(activity) { done += 1.0 }
            }
        }
        // All activities skipped or excluded → 0% (not 100%)
        if total <= 0 && skippedCount > 0 { return 0.0 }
        guard total > 0 else { return 1.0 }
        return done / total
    }

    private var groupedBySlot: [(slot: TimeSlot, activities: [Activity])] {
        var slotMap: [TimeSlot: [Activity]] = [:]
        for activity in pendingTimed {
            if activity.type == .container {
                // Expand container to each slot where it has pending children
                let children = activity.historicalChildren(on: today, from: allActivities)
                    .filter { scheduleEngine.shouldShow($0, on: today) }
                for slot in [TimeSlot.morning, .afternoon, .evening] {
                    let hasPendingChildInSlot = children.contains { child in
                        let inSlot: Bool
                        if child.isMultiSession {
                            inSlot = child.timeSlots.contains(slot)
                        } else {
                            inSlot = (child.timeWindow?.slot ?? .morning) == slot
                        }
                        // Only count if child is not completed/skipped
                        return inSlot && !isFullyCompleted(child) && !isSkipped(child)
                    }
                    if hasPendingChildInSlot {
                        slotMap[slot, default: []].append(activity)
                    }
                }
            } else if activity.isMultiSession {
                for slot in activity.timeSlots {
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
        return [TimeSlot.morning, .afternoon, .evening].compactMap { slot in
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
                        activityName: activity.name
                    ) { image in
                        if let filename = MediaService.shared.savePhoto(image, activityID: activity.id, date: today) {
                            photoPromptLog?.photoFilename = filename
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

    private var allDone: Bool {
        pendingTimed.isEmpty && stickyPending.isEmpty && !completed.isEmpty
    }

    @ViewBuilder
    private var completedSection: some View {
        if !completed.isEmpty {
            DisclosureGroup(isExpanded: $completedExpanded) {
                ForEach(completed) { activity in
                    activityView(for: activity)
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

    @ViewBuilder
    private var skippedSection: some View {
        if !skippedActivities.isEmpty {
            DisclosureGroup {
                ForEach(skippedActivities) { activity in
                    HStack(spacing: 10) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.orange)

                        Image(systemName: activity.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: activity.hexColor).opacity(0.5))
                            .frame(width: 24)

                        Text(activity.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .strikethrough(true, color: .secondary)

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
                            unskipActivity(activity)
                        } label: {
                            Text(activity.type == .container || activity.isMultiSession ? "Unskip All" : "Unskip")
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
            } label: {
                HStack {
                    Image(systemName: "forward.fill")
                        .foregroundStyle(.orange)
                    Text("SKIPPED")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("(\(skippedActivities.count))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .tint(.secondary)
        }
    }

    // MARK: - Type-Dispatched Row

    /// Default rendering (no slot context) — used by backlog, completed, skipped sections
    @ViewBuilder
    private func activityView(for activity: Activity) -> some View {
        activityView(for: activity, inSlot: nil)
    }

    /// Slot-aware rendering for time bucket sections
    @ViewBuilder
    private func activityView(for activity: Activity, inSlot slot: TimeSlot?) -> some View {
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
                    onCompleteChild: { child in completeCheckbox(child) },
                    onSkipChild: { child, reason in skipActivity(child, reason: reason) },
                    slotFilter: slot
                )
            }
        }
        .overlay(alignment: .topTrailing) {
            if let dueDate = carriedForwardOriginalDate(activity),
               !isFullyCompleted(activity), !isSkipped(activity) {
                Text("⏳ Due \(dueDate.shortWeekday)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Capsule())
                    .offset(y: -2)
            }
        }
    }

    private func carriedForwardOriginalDate(_ activity: Activity) -> Date? {
        scheduleEngine.carriedForwardDate(for: activity, on: today, logs: allLogs)
    }

    // MARK: - Completion Logic

    private func isFullyCompleted(_ activity: Activity) -> Bool {
        // Multi-session: ALL sessions must have a completion log (uniform for all types)
        if activity.isMultiSession {
            return activity.timeSlots.allSatisfy { slot in
                isSessionCompleted(activity, slot: slot)
            }
        }
        switch activity.type {
        case .checkbox, .metric, .value:
            return todayLogs.contains { $0.activity?.id == activity.id && $0.status == .completed }
        case .cumulative:
            guard let target = activity.targetValue, target > 0 else { return false }
            return cumulativeValue(for: activity) >= target
        case .container:
            let applicable = activity.historicalChildren(on: today, from: allActivities).filter { scheduleEngine.shouldShow($0, on: today) }
            guard !applicable.isEmpty else { return false }
            return applicable.allSatisfy { isFullyCompleted($0) }
        }
    }

    private func isSkipped(_ activity: Activity) -> Bool {
        if activity.type == .container {
            let applicable = activity.historicalChildren(on: today, from: allActivities).filter { scheduleEngine.shouldShow($0, on: today) }
            guard !applicable.isEmpty else { return false }
            // Container is "skipped" when all non-completed children are skipped
            let nonCompleted = applicable.filter { !isFullyCompleted($0) }
            return !nonCompleted.isEmpty && nonCompleted.allSatisfy { child in
                todayLogs.contains { $0.activity?.id == child.id && $0.status == .skipped }
            }
        }
        if activity.isMultiSession {
            // "Skipped" when all non-completed sessions are skipped
            let nonCompleted = activity.timeSlots.filter { !isSessionCompleted(activity, slot: $0) }
            return !nonCompleted.isEmpty && nonCompleted.allSatisfy { slot in
                isSessionSkipped(activity, slot: slot)
            }
        }
        return todayLogs.contains { $0.activity?.id == activity.id && $0.status == .skipped }
    }

    // MARK: - Session-Level Checks (multi-session)

    private func isSessionCompleted(_ activity: Activity, slot: TimeSlot) -> Bool {
        todayLogs.contains {
            $0.activity?.id == activity.id && $0.status == .completed && $0.timeSlot == slot
        }
    }

    private func isSessionSkipped(_ activity: Activity, slot: TimeSlot) -> Bool {
        todayLogs.contains {
            $0.activity?.id == activity.id && $0.status == .skipped && $0.timeSlot == slot
        }
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
        if let slot, activity.isMultiSession {
            if isSessionCompleted(activity, slot: slot) {
                // Uncomplete this session
                if let log = todayLogs.first(where: {
                    $0.activity?.id == activity.id && $0.status == .completed && $0.timeSlot == slot
                }) {
                    modelContext.delete(log)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showUndo("Uncompleted \(activity.name) (\(slot.displayName))") {
                        let restored = ActivityLog(activity: activity, date: today, status: .completed)
                        restored.timeSlotRaw = slot.rawValue
                        modelContext.insert(restored)
                    }
                }
                return
            }
            let log = ActivityLog(activity: activity, date: today, status: .completed)
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
            if let log = todayLogs.first(where: { $0.activity?.id == activity.id && $0.status == .completed }) {
                modelContext.delete(log)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showUndo("Uncompleted \(activity.name)") {
                    let restored = ActivityLog(activity: activity, date: today, status: .completed)
                    modelContext.insert(restored)
                }
            }
            return
        }
        
        let log = ActivityLog(activity: activity, date: today, status: .completed)
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
        if let slot, activity.isMultiSession {
            // Multi-session: find existing log for this specific slot
            if let existing = todayLogs.first(where: {
                $0.activity?.id == activity.id && $0.status == .completed && $0.timeSlot == slot
            }) {
                modelContext.delete(existing)
            }
            let log = ActivityLog(activity: activity, date: today, status: .completed, value: value)
            log.timeSlotRaw = slot.rawValue
            modelContext.insert(log)
            writeToHealthKit(activity: activity, value: value)
            if isPhotoDue(for: activity) {
                photoPromptLog = log
                photoPromptActivity = activity
            }
            return
        }
        if let existing = todayLogs.first(where: { $0.activity?.id == activity.id && $0.status == .completed }) {
            modelContext.delete(existing)
        }
        let log = ActivityLog(activity: activity, date: today, status: .completed, value: value)
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
        let log = ActivityLog(activity: activity, date: today, status: .completed, value: value)
        modelContext.insert(log)
        
        writeToHealthKit(activity: activity, value: value)
        
        showUndo("Added \(Int(value)) to \(activity.name)") { [log] in
            modelContext.delete(log)
        }
    }

    private func removeValueLog(_ activity: Activity, slot: TimeSlot? = nil) {
        let matchLog: ActivityLog?
        if let slot, activity.isMultiSession {
            matchLog = todayLogs.first(where: {
                $0.activity?.id == activity.id && $0.status == .completed && $0.timeSlot == slot
            })
        } else {
            matchLog = todayLogs.first(where: { $0.activity?.id == activity.id && $0.status == .completed })
        }
        guard let log = matchLog else { return }
        let oldValue = log.value
        let oldSlotRaw = log.timeSlotRaw
        modelContext.delete(log)
        
        showUndo("Cleared \(activity.name)") {
            let restored = ActivityLog(activity: activity, date: today, status: .completed, value: oldValue)
            restored.timeSlotRaw = oldSlotRaw
            modelContext.insert(restored)
        }
    }

    private func removeLastCumulativeLog(_ activity: Activity) {
        guard let lastLog = todayLogs.last(where: { $0.activity?.id == activity.id && $0.status == .completed }) else { return }
        let oldValue = lastLog.value
        modelContext.delete(lastLog)
        
        showUndo("Removed entry from \(activity.name)") {
            let restored = ActivityLog(activity: activity, date: today, status: .completed, value: oldValue)
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
            let log = ActivityLog(activity: activity, date: today, status: .skipped)
            log.skipReason = reason
            log.timeSlotRaw = slot.rawValue
            modelContext.insert(log)
            showUndo("Skipped \(activity.name) (\(slot.displayName))") { [log] in
                modelContext.delete(log)
            }
            return
        }

        guard !isSkipped(activity) && !isFullyCompleted(activity) else { return }
        let log = ActivityLog(activity: activity, date: today, status: .skipped)
        log.skipReason = reason
        modelContext.insert(log)        
        showUndo("Skipped \(activity.name)") { [log] in
            modelContext.delete(log)
        }
    }

    private func unskipActivity(_ activity: Activity) {
        if activity.type == .container {
            let applicable = activity.historicalChildren(on: today, from: allActivities).filter { scheduleEngine.shouldShow($0, on: today) }
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
        if activity.type == .container {
            // Return the first child's skip reason
            let applicable = activity.historicalChildren(on: today, from: allActivities).filter { scheduleEngine.shouldShow($0, on: today) }
            return applicable.compactMap { child in
                todayLogs.first(where: { $0.activity?.id == child.id && $0.status == .skipped })?.skipReason
            }.first
        }
        return todayLogs.first(where: {
            $0.activity?.id == activity.id && $0.status == .skipped
        })?.skipReason
    }

    private func showUndo(_ message: String, action: @escaping () -> Void) {
        undoMessage = message
        undoAction = action
        showUndoToast = true
    }

    // MARK: - Value Queries

    private func latestValue(for activity: Activity, slot: TimeSlot? = nil) -> Double? {
        if let slot, activity.isMultiSession {
            return todayLogs.first(where: {
                $0.activity?.id == activity.id && $0.status == .completed && $0.timeSlot == slot
            })?.value
        }
        return todayLogs.first(where: { $0.activity?.id == activity.id && $0.status == .completed })?.value
    }

    private func cumulativeValue(for activity: Activity) -> Double {
        let values = todayLogs
            .filter { $0.activity?.id == activity.id && $0.status == .completed }
            .compactMap(\.value)
        return activity.aggregateDayValue(from: values)
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

