import SwiftUI
import SwiftData

struct AddActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \Activity.sortOrder) private var allActivities: [Activity]

    @State private var name = ""
    @State private var selectedIcon = "circle"
    @State private var selectedColor = "#007AFF"
    @State private var selectedType: ActivityType = .checkbox
    
    // Schedule UI State
    @State private var scheduleMode: ScheduleMode = .recurring
    @State private var scheduleType: ScheduleType = .daily
    @State private var selectedWeekdays: Set<Int> = []
    @State private var selectedSlot: TimeSlot = .morning
    @State private var isMultiSession: Bool = false
    @State private var selectedSlots: Set<TimeSlot> = [.morning, .evening]
    @State private var selectedCategory: Category?

    // Value / Cumulative config
    @State private var targetValueText = ""
    @State private var unit = ""

    // Schedule config
    @State private var selectedMonthDays: Set<Int> = []
    @State private var adhocDate = Date()

    // Composable inputs
    @State private var allowsPhoto = false
    @State private var photoCadence: PhotoCadence = .never
    @State private var allowsNotes = false

    // Reminders
    @State private var enableReminder = false
    @State private var reminderType: ReminderType = .time
    @State private var reminderTime = Date()
    @State private var periodicInterval = 4

    // HealthKit
    @State private var enableHealthKit = false
    @State private var hkType = "stepCount"
    @State private var hkMode = "read"

    // Container config
    @State private var selectedParent: Activity?
    @State private var isSubActivity = false
    
    // Edit scope dialog (Future Only vs All Changes)
    @State private var showEditScopeDialog = false
    @State private var pendingSchedule: Schedule?
    @State private var pendingReminder: ReminderPreset?
    
    // Edit Mode
    var activityToEdit: Activity?
    
    // Pre-configuration (e.g. quick-add from container)
    var presetParent: Activity?

    private let iconOptions = [
        "circle", "star", "heart", "bolt", "flame",
        "drop.fill", "pills.fill", "figure.run", "dumbbell",
        "book", "brain", "cross.case.fill", "cup.and.saucer",
        "bed.double", "leaf", "eye", "hand.raised",
        "pencil", "music.note", "phone",
    ]

    private let colorOptions = [
        "#FF6B35", "#4ECDC4", "#45B7D1", "#FF6B6B",
        "#C44DFF", "#96CEB4", "#FFEAA7", "#74B9FF",
        "#A29BFE", "#FD79A8", "#00B894", "#E17055",
    ]

    private let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// Existing container activities for "add as sub-activity"
    private var containerActivities: [Activity] {
        allActivities.filter { $0.type == .container && $0.id != activityToEdit?.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                typeSection
                typeSpecificSection
                categorySection
                scheduleSection
                if selectedType != .container {
                    timeWindowSection
                }
                parentSection
                appearanceSection
                composableInputsSection
                notificationsSection
                if selectedType != .container {
                    healthKitSection
                }
                
                if activityToEdit != nil {
                    Section {
                        if activityToEdit?.isStopped == true {
                            Button("Resume Tracking") {
                                resumeTracking()
                            }
                            .foregroundStyle(.green)
                        } else {
                            Button("Stop Tracking") {
                                stopTracking()
                            }
                            .foregroundStyle(.orange)
                        }

                        Button("Archive Activity", role: .destructive) {
                            archiveActivity()
                        }
                    } footer: {
                        if activityToEdit?.isStopped == true {
                            Text("This activity is paused. Past records are preserved.")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .navigationTitle(activityToEdit == nil ? "New Activity" : "Edit Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let activity = activityToEdit {
                    loadData(from: activity)
                } else if let parent = presetParent {
                    isSubActivity = true
                    selectedParent = parent
                }
            }
            .confirmationDialog(
                "How should this change apply?",
                isPresented: $showEditScopeDialog,
                titleVisibility: .visible
            ) {
                Button("Future Only") {
                    guard let activity = activityToEdit,
                          let sched = pendingSchedule,
                          let rem = pendingReminder else { return }
                    performSave(activity: activity, schedule: sched, reminder: rem, futureOnly: true)
                    dismiss()
                }
                Button("All Changes") {
                    guard let activity = activityToEdit,
                          let sched = pendingSchedule,
                          let rem = pendingReminder else { return }
                    performSave(activity: activity, schedule: sched, reminder: rem, futureOnly: false)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\"Future Only\" preserves past analytics with the old settings. \"All Changes\" updates everything retroactively.")
            }
        }
    }
    
    // MARK: - Load Data
    
    private func loadData(from activity: Activity) {
        name = activity.name
        selectedIcon = activity.icon
        selectedColor = activity.hexColor
        selectedType = activity.type 
        
        // Restore Schedule
        let schedule = activity.schedule
        scheduleType = schedule.type
        if let weekdays = schedule.weekdays { selectedWeekdays = Set(weekdays) }
        if let monthDays = schedule.monthDays { selectedMonthDays = Set(monthDays) }
        if let date = schedule.specificDate { adhocDate = date }
        
        // Map to Mode
        switch scheduleType {
        case .daily, .weekly, .monthly: scheduleMode = .recurring
        case .adhoc: scheduleMode = .oneTime
        case .sticky: scheduleMode = .backlog
        }
        
        // Restore TimeWindow
        if let tw = activity.timeWindow {
            selectedSlot = tw.slot
        }
        // Restore multi-session
        if activity.isMultiSession {
            isMultiSession = true
            selectedSlots = Set(activity.timeSlots)
        }
        
        // Restore Config
        if let u = activity.unit { unit = u }
        if let t = activity.targetValue { targetValueText = String(format: "%.0f", t) }
        
        allowsPhoto = activity.allowsPhoto
        photoCadence = activity.photoCadence
        allowsNotes = activity.allowsNotes
        
        // Restore Category/Parent
        selectedCategory = activity.category
        if let parent = activity.parent {
            isSubActivity = true
            selectedParent = parent
        }
        
        // Restore Reminder
        if let reminder = activity.reminder {
            switch reminder {
            case .none:
                enableReminder = false
            case .morningNudge:
                enableReminder = true
                reminderType = .morning
            case .eveningCheckIn:
                enableReminder = true
                reminderType = .evening
            case .periodic(let hours):
                enableReminder = true
                reminderType = .periodic
                periodicInterval = hours
            case .remindAt(let h, let m):
                enableReminder = true
                reminderType = .time
                var comps = DateComponents()
                comps.hour = h
                comps.minute = m
                reminderTime = Calendar.current.date(from: comps) ?? Date()
            }
        } else {
            enableReminder = false
        }
        
        // Restore HealthKit
        if let hkID = activity.healthKitTypeID {
            enableHealthKit = true
            hkType = hkID
            hkMode = activity.healthKitModeRaw ?? "read"
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            TextField("Activity name", text: $name)
                .font(.title3)
        }
    }

    private var typeSection: some View {
        Section("Type") {
            Picker("Type", selection: $selectedType) {
                ForEach(ActivityType.allCases) { type in
                    Label(type.displayName, systemImage: type.systemImage).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedType) { _, newType in
                if newType == .cumulative { selectedSlot = .allDay }
            }
        }
    }

    @ViewBuilder
    private var typeSpecificSection: some View {
        switch selectedType {
        case .value:
            Section("Value Configuration") {
                TextField("Unit (e.g., kg, hrs)", text: $unit)
            }
        case .cumulative:
            Section("Target") {
                TextField("Daily target (e.g., 2000)", text: $targetValueText)
                    .keyboardType(.decimalPad)
                TextField("Unit (e.g., ml, steps)", text: $unit)
            }
        case .container:
            Section {
                Text("Container will derive completion from its sub-activities.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .checkbox:
            EmptyView()
        }
    }

    private var categorySection: some View {
        Section("Category") {
            Picker("Category", selection: $selectedCategory) {
                Text("None").tag(Category?.none)
                ForEach(categories) { cat in
                    Label(cat.name, systemImage: cat.icon)
                        .tag(Optional(cat))
                }
            }
            .disabled(categoryInherited)
            
            if categoryInherited {
                Text("Inherited from parent container")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            if selectedType != .container {
                // High level mode
                Picker("Mode", selection: $scheduleMode) {
                    Text("Recurring").tag(ScheduleMode.recurring)
                    Text("One-Time").tag(ScheduleMode.oneTime)
                    Text("Anytime").tag(ScheduleMode.backlog)
                }
                .pickerStyle(.segmented)
                .onChange(of: scheduleMode) { _, newMode in
                    switch newMode {
                    case .recurring:
                        if ![.daily, .weekly, .monthly].contains(scheduleType) {
                            scheduleType = .daily
                        }
                    case .oneTime: scheduleType = .adhoc
                    case .backlog: scheduleType = .sticky
                    }
                }
                
                // Detail configuration
                if scheduleMode == .recurring {
                    Picker("Frequency", selection: $scheduleType) {
                        Text("Daily").tag(ScheduleType.daily)
                        Text("Weekly").tag(ScheduleType.weekly)
                        Text("Monthly").tag(ScheduleType.monthly)
                    }
                    
                    if scheduleType == .weekly {
                        weekdayPicker
                    } else if scheduleType == .monthly {
                        monthlyPicker
                    }
                } else if scheduleMode == .oneTime {
                    DatePicker("Date", selection: $adhocDate, displayedComponents: .date)
                } else if scheduleMode == .backlog {
                    Text("Tasks that sit in your backlog until completed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Containers follow their children's schedules")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let isSelected = selectedWeekdays.contains(day)
                Button {
                    if isSelected { selectedWeekdays.remove(day) }
                    else { selectedWeekdays.insert(day) }
                } label: {
                    Text(weekdayNames[day - 1])
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var monthlyPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(1...31, id: \.self) { day in
                let isSelected = selectedMonthDays.contains(day)
                Button {
                    if isSelected { selectedMonthDays.remove(day) }
                    else { selectedMonthDays.insert(day) }
                } label: {
                    Text("\(day)")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var timeWindowSection: some View {
        Section("Time of Day") {
            if !isMultiSession {
                Picker("When", selection: $selectedSlot) {
                    ForEach([TimeSlot.allDay, .morning, .afternoon, .evening], id: \.self) { slot in
                        Label(slot.displayName, systemImage: slot.icon).tag(slot)
                    }
                }
                .pickerStyle(.segmented)
            }

            if selectedSlot != .allDay || isMultiSession {
                Toggle("Repeat across time periods", isOn: $isMultiSession)
                    .onChange(of: isMultiSession) { _, on in
                        if on {
                            // Default to morning + evening if nothing selected
                            if selectedSlots.isEmpty {
                                selectedSlots = [.morning, .evening]
                            }
                        }
                    }
            }

            if isMultiSession {
                ForEach([TimeSlot.morning, .afternoon, .evening], id: \.self) { slot in
                    Button {
                        if selectedSlots.contains(slot) {
                            if selectedSlots.count > 1 { selectedSlots.remove(slot) }
                        } else {
                            selectedSlots.insert(slot)
                        }
                    } label: {
                        HStack {
                            Image(systemName: slot.icon)
                                .foregroundStyle(selectedSlots.contains(slot) ? .primary : .secondary)
                            Text(slot.displayName)
                            Spacer()
                            if selectedSlots.contains(slot) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    @ViewBuilder
    private var parentSection: some View {
        if !containerActivities.isEmpty && selectedType != .container {
            Section("Add as Sub-Activity") {
                Toggle("Part of a routine", isOn: $isSubActivity)

                if isSubActivity {
                    Picker("Parent", selection: $selectedParent) {
                        Text("None").tag(Activity?.none)
                        ForEach(containerActivities) { parent in
                            Text(parent.name).tag(Optional(parent))
                        }
                    }
                    .onChange(of: selectedParent) { _, newParent in
                        if let parentCategory = newParent?.category {
                            selectedCategory = parentCategory
                        }
                    }
                }
            }
        }
    }

    /// Category is inherited from parent when sub-activity
    private var categoryInherited: Bool {
        isSubActivity && selectedParent?.category != nil
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(iconOptions, id: \.self) { icon in
                        Button { selectedIcon = icon } label: {
                            Image(systemName: icon)
                                .font(.system(size: 18))
                                .frame(width: 38, height: 38)
                                .background(selectedIcon == icon ? Color(hex: selectedColor).opacity(0.3) : Color(.tertiarySystemFill))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(selectedIcon == icon ? Color(hex: selectedColor) : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(colorOptions, id: \.self) { color in
                        Button { selectedColor = color } label: {
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if selectedColor == color {
                                        Image(systemName: "checkmark")
                                            .font(.caption).fontWeight(.bold)
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var composableInputsSection: some View {
        if selectedType != .container {
            Section("Composable Inputs") {
                // Photos don't apply to cumulative activities
                if selectedType != .cumulative {
                    Toggle(isOn: $allowsPhoto) {
                        Label("Photo Tracking", systemImage: "camera")
                    }
                    if allowsPhoto {
                        Picker(selection: $photoCadence) {
                            ForEach(PhotoCadence.allCases.filter { $0 != .never }) { cadence in
                                Text(cadence.displayName).tag(cadence)
                            }
                        } label: {
                            Label("Capture Cadence", systemImage: "clock.arrow.circlepath")
                        }
                        Text(photoCadence.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $allowsNotes) {
                    Label("Notes", systemImage: "note.text")
                }
            }
            .onChange(of: allowsPhoto) { _, newValue in
                if newValue && photoCadence == .never {
                    photoCadence = .weekly
                }
                if !newValue {
                    photoCadence = .never
                }
            }
            .onChange(of: selectedType) { _, newType in
                if newType == .cumulative {
                    allowsPhoto = false
                    photoCadence = .never
                }
            }
        }
    }

    // MARK: - Advanced Integrations

    @ViewBuilder
    private var notificationsSection: some View {
        if selectedType == .container {
            Section("Reminders") {
                Toggle("Nudge if incomplete", isOn: $enableReminder)
                if enableReminder {
                    Text("You'll get an evening reminder if any child activity is incomplete.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Section("Reminders") {
                Toggle("Enable Reminder", isOn: $enableReminder)

                if enableReminder {
                    Picker("Type", selection: $reminderType) {
                        Text("Time").tag(ReminderType.time)
                        Text("Morning Nudge").tag(ReminderType.morning)
                        Text("Evening Check-In").tag(ReminderType.evening)
                        Text("Periodic").tag(ReminderType.periodic)
                    }

                    if reminderType == .time {
                        DatePicker("At", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    } else if reminderType == .periodic {
                        Stepper("Every \(periodicInterval) hours", value: $periodicInterval, in: 1...12)
                    }
                }
            }
        }
    }

    private var healthKitSection: some View {
        Section("HealthKit") {
            Toggle("Link to Health", isOn: $enableHealthKit)

            if enableHealthKit {
                Picker("Data Type", selection: $hkType) {
                    Text("Steps").tag("stepCount")
                    Text("Walking Check").tag("appleWalkingSteadiness") 
                    Text("Water").tag("dietaryWater")
                    Text("Weight").tag("bodyMass")
                    Text("Sleep").tag("sleepAnalysis")
                    Text("Workout").tag("workout")
                }
                
                Picker("Mode", selection: $hkMode) {
                    Text("Read Only").tag("read")
                    Text("Write Only").tag("write")
                    Text("Read & Write").tag("both")
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Save

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let schedule: Schedule
        if selectedType == .container {
            schedule = .daily // containers auto-show based on children
        } else {
            switch scheduleType {
            case .daily: schedule = .daily
            case .weekly: schedule = .weekly(Array(selectedWeekdays).sorted())
            case .monthly: schedule = .monthly(Array(selectedMonthDays).sorted())
            case .sticky: schedule = .sticky
            case .adhoc: schedule = .adhoc(adhocDate)
            }
        }
        
        // Reminder
        let reminder: ReminderPreset
        if enableReminder {
            if selectedType == .container {
                // Container nudge: evening check-in for incomplete children
                reminder = .eveningCheckIn
            } else {
                switch reminderType {
                case .time:
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                    reminder = .remindAt(hour: comps.hour ?? 9, minute: comps.minute ?? 0)
                case .morning: reminder = .morningNudge
                case .evening: reminder = .eveningCheckIn
                case .periodic: reminder = .periodic(hours: periodicInterval)
                }
            }
        } else {
            reminder = .none
        }

        if let activity = activityToEdit {
            // Always ask when activity has logs — simpler, more robust
            if !activity.logs.isEmpty {
                pendingSchedule = schedule
                pendingReminder = reminder
                showEditScopeDialog = true
                return
            }

            performSave(activity: activity, schedule: schedule, reminder: reminder, futureOnly: false)
        } else {
            // Insert New
            let activity = Activity(
                name: trimmed,
                icon: selectedIcon,
                hexColor: selectedColor,
                type: selectedType,
                schedule: schedule,
                timeWindow: selectedType != .container ? TimeWindow(slot: isMultiSession ? (selectedSlots.sorted().first ?? .morning) : selectedSlot) : nil,
                category: selectedCategory
            )

            // Multi-session support
            if isMultiSession && selectedSlots.count > 1 {
                activity.timeSlots = selectedSlots.sorted()
            }
            
            activity.reminder = reminder
            
            if selectedType != .container {
                activity.allowsPhoto = allowsPhoto
                activity.photoCadence = allowsPhoto ? photoCadence : .never
                activity.allowsNotes = allowsNotes
            }
            
            if selectedType == .value || selectedType == .cumulative {
                activity.unit = unit.isEmpty ? nil : unit
            }
            if selectedType == .cumulative, let target = Double(targetValueText) {
                activity.targetValue = target
            }
            
            if isSubActivity, let parent = selectedParent {
                activity.parent = parent
            }
            
            if selectedType != .container && enableHealthKit {
                activity.healthKitTypeID = hkType
                activity.healthKitModeRaw = hkMode
            }
            
            modelContext.insert(activity)
        }
        
        dismiss()
    }
    
    private func archiveActivity() {
        if let activity = activityToEdit {
            activity.isArchived = true
            dismiss()
        }
    }

    private func stopTracking() {
        if let activity = activityToEdit {
            activity.stoppedAt = Date().startOfDay
            dismiss()
        }
    }

    private func resumeTracking() {
        if let activity = activityToEdit {
            activity.stoppedAt = nil
            dismiss()
        }
    }


    // MARK: - Perform Save (with optional snapshot)

    private func performSave(activity: Activity, schedule: Schedule, reminder: ReminderPreset, futureOnly: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        // Snapshot current config before mutation if future-only
        if futureOnly {
            let effectiveFrom = activity.configSnapshots
                .compactMap { $0.effectiveUntil }
                .max()
                .map { Calendar.current.date(byAdding: .day, value: 1, to: $0) ?? $0 }
                ?? activity.createdAt

            let snapshot = ActivityConfigSnapshot(
                activity: activity,
                effectiveFrom: effectiveFrom,
                effectiveUntil: Calendar.current.date(byAdding: .day, value: -1, to: Date().startOfDay) ?? Date().startOfDay
            )
            modelContext.insert(snapshot)
        }

        // Apply all changes to the activity
        activity.name = trimmed
        activity.icon = selectedIcon
        activity.hexColor = selectedColor
        activity.type = selectedType
        activity.scheduleData = try? JSONEncoder().encode(schedule)
        activity.category = selectedCategory
        activity.reminderData = try? JSONEncoder().encode(reminder)

        if selectedType != .container {
            if isMultiSession && selectedSlots.count > 1 {
                let primarySlot = selectedSlots.sorted().first ?? .morning
                activity.timeWindowData = try? JSONEncoder().encode(TimeWindow(slot: primarySlot))
                activity.timeSlots = selectedSlots.sorted()
            } else {
                activity.timeWindowData = try? JSONEncoder().encode(TimeWindow(slot: selectedSlot))
                activity.timeSlotsData = nil
            }
            activity.allowsPhoto = allowsPhoto
            activity.photoCadence = allowsPhoto ? photoCadence : .never
            activity.allowsNotes = allowsNotes
        } else {
            activity.timeWindowData = nil
            activity.allowsPhoto = false
            activity.allowsNotes = false
        }

        if selectedType == .value || selectedType == .cumulative {
            activity.unit = unit.isEmpty ? nil : unit
        }
        if selectedType == .cumulative, let target = Double(targetValueText) {
            activity.targetValue = target
        }

        if isSubActivity, let parent = selectedParent {
            activity.parent = parent
        } else {
            activity.parent = nil
        }

        if enableHealthKit {
            activity.healthKitTypeID = hkType
            activity.healthKitModeRaw = hkMode
        } else {
            activity.healthKitTypeID = nil
            activity.healthKitModeRaw = nil
        }
    }
}

// Helper Enums for UI state
enum ReminderType: String, CaseIterable, Identifiable {
    case time, morning, evening, periodic
    var id: String { rawValue }
}

enum ScheduleMode {
    case recurring, oneTime, backlog
}
