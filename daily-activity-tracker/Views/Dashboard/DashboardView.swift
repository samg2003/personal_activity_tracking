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

    /// Activities that have at least one pending session (for multi-session grouping)
    private var pendingTimedIncludingPartial: [Activity] {
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
        // Multi-session activities count as N items (one per slot)
        var total = 0
        var done = 0
        for activity in todayActivities {
            if isSkipped(activity) { continue }
            let sessions = activity.isMultiSession ? activity.timeSlots.count : 1
            total += sessions
            if isFullyCompleted(activity) {
                done += sessions
            } else if activity.isMultiSession {
                // Count individually completed sessions
                for slot in activity.timeSlots {
                    if isSessionCompleted(activity, slot: slot) { done += 1 }
                }
            }
        }
        guard total > 0 else { return 1.0 }
        return Double(done) / Double(total)
    }

    private var groupedBySlot: [(slot: TimeSlot, activities: [Activity])] {
        // Build slot→activities mapping, expanding multi-session activities
        var slotMap: [TimeSlot: [Activity]] = [:]
        for activity in pendingTimed {
            if activity.isMultiSession {
                for slot in activity.timeSlots {
                    // Only include in this slot if the session isn't already completed/skipped
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
                    DatePickerBar(selectedDate: $selectedDate, vacationDays: vacationDays)
                    
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
        let total = cumulativeTotal(for: activity)
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
            cumulativeValues: { cumulativeTotal(for: $0) },
            onAdd: { activity, value in addCumulativeLog(activity, value: value) },
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

    @ViewBuilder
    private var completedSection: some View {
        if !completed.isEmpty {
            DisclosureGroup {
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
            case .checkbox:
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
                ValueInputRow(
                    activity: activity,
                    currentValue: latestValue(for: activity),
                    onLog: { value in logValue(activity, value: value) },
                    onRemove: { removeValueLog(activity) },
                    onTakePhoto: activity.allowsPhoto ? {
                        triggerPhotoPrompt(for: activity)
                    } : nil
                )
            case .cumulative:
                ValueInputRow(
                    activity: activity,
                    currentValue: cumulativeTotal(for: activity),
                    onLog: { value in addCumulativeLog(activity, value: value) },
                    onShowLogs: { logSheetActivity = activity }
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
    }

    // MARK: - Completion Logic

    private func isFullyCompleted(_ activity: Activity) -> Bool {
        switch activity.type {
        case .checkbox:
            if activity.isMultiSession {
                // ALL sessions must have a completion log
                return activity.timeSlots.allSatisfy { slot in
                    isSessionCompleted(activity, slot: slot)
                }
            }
            return todayLogs.contains { $0.activity?.id == activity.id && $0.status == .completed }
        case .value:
            return todayLogs.contains { $0.activity?.id == activity.id && $0.status == .completed }
        case .cumulative:
            guard let target = activity.targetValue, target > 0 else { return false }
            return cumulativeTotal(for: activity) >= target
        case .container:
            let applicable = activity.children.filter { scheduleEngine.shouldShow($0, on: today) }
            guard !applicable.isEmpty else { return true }
            return applicable.allSatisfy { isFullyCompleted($0) }
        }
    }

    private func isSkipped(_ activity: Activity) -> Bool {
        if activity.type == .container {
            let applicable = activity.children.filter { scheduleEngine.shouldShow($0, on: today) }
            guard !applicable.isEmpty else { return false }
            return applicable.allSatisfy { child in
                todayLogs.contains { $0.activity?.id == child.id && $0.status == .skipped }
            }
        }
        if activity.isMultiSession {
            // Container-like: all sessions must be skipped
            return activity.timeSlots.allSatisfy { slot in
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

    /// Checks whether a photo prompt should be triggered based on cadence
    private func isPhotoDue(for activity: Activity) -> Bool {
        let cadence = activity.photoCadence
        guard cadence != .never else { return false }
        if cadence == .everyTime { return true }

        // Find the most recent log with a photo for this activity
        let logsWithPhotos = allLogs.filter {
            $0.activity?.id == activity.id && $0.photoFilename != nil
        }
        guard let lastPhotoDate = logsWithPhotos.map({ $0.date }).max() else {
            return true // Never taken a photo, definitely due
        }

        let calendar = Calendar.current
        let now = Date()
        switch cadence {
        case .weekly:
            let daysSince = calendar.dateComponents([.day], from: lastPhotoDate, to: now).day ?? 0
            return daysSince >= 7
        case .monthly:
            let daysSince = calendar.dateComponents([.day], from: lastPhotoDate, to: now).day ?? 0
            return daysSince >= 30
        case .everyTime, .never:
            return false
        }
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

            if activity.allowsPhoto && isPhotoDue(for: activity) {
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
        
        NotificationService.shared.cancelReminders(for: activity.id)
        writeToHealthKit(activity: activity, value: 1.0)
        
        if activity.allowsPhoto && isPhotoDue(for: activity) {
            triggerPhotoPrompt(for: activity, log: log)
        }
        
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
        
        // Integrations
        NotificationService.shared.cancelReminders(for: activity.id)
        writeToHealthKit(activity: activity, value: value)

        // Photo cadence check for value activities
        if activity.allowsPhoto && isPhotoDue(for: activity) {
            photoPromptLog = log
            photoPromptActivity = activity
        }
    }

    private func addCumulativeLog(_ activity: Activity, value: Double) {
        let log = ActivityLog(activity: activity, date: today, status: .completed, value: value)
        modelContext.insert(log)
        
        // Integrations
        if isFullyCompleted(activity) {
            NotificationService.shared.cancelReminders(for: activity.id)
        }
        writeToHealthKit(activity: activity, value: value)
        
        showUndo("Added \(Int(value)) to \(activity.name)") { [log] in
            modelContext.delete(log)
        }
    }

    private func removeValueLog(_ activity: Activity) {
        guard let log = todayLogs.first(where: { $0.activity?.id == activity.id && $0.status == .completed }) else { return }
        let oldValue = log.value
        modelContext.delete(log)
        
        showUndo("Cleared \(activity.name)") {
            let restored = ActivityLog(activity: activity, date: today, status: .completed, value: oldValue)
            modelContext.insert(restored)
        }
    }

    private func removeLastCumulativeLog(_ activity: Activity) {
        guard let lastLog = todayLogs.first(where: { $0.activity?.id == activity.id && $0.status == .completed }) else { return }
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
        } else {
            if let existing = vacationDays.first(where: { $0.date.isSameDay(as: date) }) {
                modelContext.delete(existing)
            }
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
        
        NotificationService.shared.cancelReminders(for: activity.id)
        
        showUndo("Skipped \(activity.name)") { [log] in
            modelContext.delete(log)
        }
    }

    private func unskipActivity(_ activity: Activity) {
        if activity.type == .container {
            let applicable = activity.children.filter { scheduleEngine.shouldShow($0, on: today) }
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
            let applicable = activity.children.filter { scheduleEngine.shouldShow($0, on: today) }
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
                let unit: HKUnit = activity.unit == "ml" ? .literUnit(with: .milli) : .count() 
                // TODO: Robust unit mapping based on typeID. For now, basic fallback.
                // Refinement: Add a helper in HealthKitService to get default unit for type.
                
                let value = try? await HealthKitService.shared.readTotalToday(for: hkType, unit: unit)
                if let val = value, val > 0 {
                    // Update log if value differs significantly or missing
                    let current = latestValue(for: activity) ?? cumulativeTotal(for: activity)
                    if abs(current - val) > 0.1 {
                        // Auto-log from HealthKit
                        await MainActor.run {
                            // If cumulative, we might need to be careful not to double add?
                            // Actually, readTotalToday returns the SUM.
                            // If we have local logs provided by user, do we overwrite?
                            // Strategy: For HK synced activities, the "Truth" is HK.
                            // We replace today's logs with a single "HealthKit Sync" log?
                            // Or we strictly use HK value.
                            
                            // Simple approach: Delete existing logs for today, insert one "HealthKit Import".
                            let existing = todayLogs.filter { $0.activity?.id == activity.id }
                            existing.forEach { modelContext.delete($0) }
                            
                            let log = ActivityLog(activity: activity, date: today, status: .completed, value: val)
                            log.note = "Synced from HealthKit"
                            modelContext.insert(log)
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
            let unit: HKUnit = activity.unit == "ml" ? .literUnit(with: .milli) : .count()
            try? await HealthKitService.shared.writeSample(type: hkType, value: value, unit: unit, date: Date())
        }
    }
}

