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
    @State private var selectedAggregation: AggregationMode = .sum

    // Schedule config
    @State private var selectedMonthDays: Set<Int> = []
    @State private var adhocDate = Date()

    // Metric config (only when type == .metric)
    @State private var selectedMetricKind: MetricKind = .value

    // HealthKit
    @State private var enableHealthKit = false
    @State private var hkType = "stepCount"
    @State private var hkMode = "read"

    // Container config
    @State private var selectedParent: Activity?
    @State private var isSubActivity = false
    
    // Tracks whether appearance/category/unit was auto-set (reset on manual override)
    @State private var appearanceAutoSet = true
    @State private var categoryAutoSet = true
    @State private var unitAutoSet = true
    @State private var settingCategoryFromSuggestion = false
    @State private var settingUnitFromSuggestion = false
    @State private var showAdvancedOptions = false
    
    // Edit scope dialog (Future Only vs All Changes)
    @State private var showEditScopeDialog = false
    @State private var pendingSchedule: Schedule?
    
    // Edit Mode
    var activityToEdit: Activity?
    
    // Pre-configuration (e.g. quick-add from container)
    var presetParent: Activity?

    private let iconCategories: [(name: String, icons: [String])] = [
        ("Fitness", [
            "figure.run", "figure.walk", "figure.hiking", "figure.cooldown",
            "figure.yoga", "dumbbell.fill", "figure.strengthtraining.traditional",
            "figure.highintensity.intervaltraining", "figure.step.training",
            "bicycle", "figure.swimming", "figure.rowing",
            "soccerball", "basketball.fill", "tennisball.fill",
            "hand.raised.fill", "flame.fill",
        ]),
        ("Nutrition", [
            "drop.fill", "cup.and.saucer.fill", "mug.fill",
            "fork.knife", "leaf.fill", "carrot.fill",
            "takeoutbag.and.cup.and.straw.fill",
        ]),
        ("Sleep", [
            "bed.double.fill", "moon.fill", "moon.zzz.fill",
            "sunrise.fill", "powersleep",
        ]),
        ("Mind", [
            "brain.head.profile.fill", "brain.fill", "wind",
            "sparkles", "heart.fill", "face.smiling.fill",
        ]),
        ("Learning", [
            "book.fill", "books.vertical.fill", "character.book.closed.fill",
            "headphones", "newspaper.fill", "graduationcap.fill",
            "pencil", "pencil.and.outline",
        ]),
        ("Work", [
            "laptopcomputer", "desktopcomputer", "briefcase.fill",
            "doc.text.fill", "list.bullet.clipboard.fill",
            "calendar", "clock.fill",
        ]),
        ("Hygiene", [
            "shower.fill", "drop.circle.fill", "mouth.fill",
            "comb.fill",
        ]),
        ("Health", [
            "pills.fill", "cross.case.fill", "heart.text.square.fill",
            "stethoscope", "waveform.path.ecg",
        ]),
        ("Money", [
            "dollarsign.circle.fill", "creditcard.fill",
            "banknote.fill", "chart.line.uptrend.xyaxis",
        ]),
        ("Social", [
            "person.2.fill", "figure.2.and.child.holdinghands",
            "phone.fill", "bubble.left.fill",
            "heart.circle.fill", "hand.thumbsup.fill",
        ]),
        ("Home", [
            "house.fill", "bubbles.and.sparkles.fill", "washer.fill",
            "frying.pan.fill", "cart.fill",
        ]),
        ("Outdoors", [
            "sun.max.fill", "tree.fill", "mountain.2.fill",
            "camera.fill",
        ]),
        ("Other", [
            "star.fill", "bolt.fill", "circle", "checkmark.circle",
            "eye", "music.note", "gamecontroller.fill",
            "iphone.slash", "paintpalette.fill",
        ]),
    ]

    @State private var iconSearchText = ""

    private var filteredIconCategories: [(name: String, icons: [String])] {
        guard !iconSearchText.isEmpty else { return iconCategories }
        let q = iconSearchText.lowercased()
        return iconCategories.compactMap { cat in
            let matched = cat.icons.filter { $0.lowercased().contains(q) || cat.name.lowercased().contains(q) }
            return matched.isEmpty ? nil : (cat.name, matched)
        }
    }


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
                scheduleSection

                // Category and Time of Day always visible
                categorySection
                if selectedType != .container {
                    timeWindowSection
                }

                // Advanced options only for remaining sections
                let showAll = activityToEdit != nil || showAdvancedOptions
                if showAll {
                    parentSection
                    if selectedType != .container && selectedType != .metric {
                        healthKitSection
                    }
                    appearanceSection
                }
                if activityToEdit == nil {
                    Section {
                        Button {
                            withAnimation { showAdvancedOptions.toggle() }
                        } label: {
                            HStack {
                                Label(
                                    showAdvancedOptions ? "Less Options" : "More Options",
                                    systemImage: showAdvancedOptions ? "chevron.up" : "chevron.down"
                                )
                                .font(.subheadline)
                                Spacer()
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if activityToEdit != nil {
                    Section {
                        if activityToEdit?.isStopped == true {
                            Button("Resume Activity") {
                                resumeTracking()
                            }
                            .foregroundStyle(.green)
                        } else {
                            Button("Pause Activity", role: .destructive) {
                                pauseTracking()
                            }
                        }
                    } footer: {
                        if activityToEdit?.isStopped == true {
                            Text("This activity is paused. Past records are preserved. Tap Resume to reactivate.")
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
                          let sched = pendingSchedule else { return }
                    performSave(activity: activity, schedule: sched, futureOnly: true)
                    dismiss()
                }
                Button("All Changes") {
                    guard let activity = activityToEdit,
                          let sched = pendingSchedule else { return }
                    performSave(activity: activity, schedule: sched, futureOnly: false)
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
        appearanceAutoSet = false
        categoryAutoSet = false
        unitAutoSet = false
        
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
        selectedAggregation = activity.aggregationMode
        
        // Restore Metric Kind
        if let kind = activity.metricKind {
            selectedMetricKind = kind
        }
        
        // Restore Category/Parent
        selectedCategory = activity.category
        if let parent = activity.parent {
            isSubActivity = true
            selectedParent = parent
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
                .onChange(of: name) { _, newName in
                    if appearanceAutoSet {
                        let suggestion = ActivityAppearance.suggest(
                            for: newName, type: selectedType, metricKind: selectedMetricKind
                        )
                        selectedIcon = suggestion.icon
                        selectedColor = suggestion.color
                    }
                    // Smart category autofill from title
                    if categoryAutoSet && !categoryInherited {
                        settingCategoryFromSuggestion = true
                        if let suggestedName = ActivityAppearance.suggestCategory(for: newName),
                           let match = categories.first(where: { $0.name.localizedCaseInsensitiveCompare(suggestedName) == .orderedSame }) {
                            selectedCategory = match
                        } else {
                            selectedCategory = nil
                        }
                        settingCategoryFromSuggestion = false
                    }
                    // Smart unit autofill — pre-set for when user picks a numeric type
                    if unitAutoSet {
                        settingUnitFromSuggestion = true
                        if let suggestedUnit = ActivityAppearance.suggestUnit(for: newName) {
                            unit = suggestedUnit
                        } else {
                            unit = ""
                        }
                        settingUnitFromSuggestion = false
                    }
                }
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
                // Re-fire appearance auto-suggest on type change
                if appearanceAutoSet {
                    let suggestion = ActivityAppearance.suggest(
                        for: name, type: newType, metricKind: selectedMetricKind
                    )
                    selectedIcon = suggestion.icon
                    selectedColor = suggestion.color
                }
                // Re-fire unit suggestion when switching to a numeric type
                if unitAutoSet && (newType == .value || newType == .cumulative || newType == .metric) {
                    settingUnitFromSuggestion = true
                    if let suggestedUnit = ActivityAppearance.suggestUnit(for: name) {
                        unit = suggestedUnit
                    }
                    settingUnitFromSuggestion = false
                }
            }
        }
    }

    @ViewBuilder
    private var typeSpecificSection: some View {
        switch selectedType {
        case .value:
            Section("Value Configuration") {
                UnitPicker(selection: $unit)
                    .onChange(of: unit) { _, _ in
                        if !settingUnitFromSuggestion { unitAutoSet = false }
                    }
            }
        case .cumulative:
            Section("Target") {
                TextField("Daily target (e.g., 2000)", text: $targetValueText)
                    .keyboardType(.decimalPad)
                UnitPicker(selection: $unit)
                    .onChange(of: unit) { _, _ in
                        if !settingUnitFromSuggestion { unitAutoSet = false }
                    }
                Picker("Aggregation", selection: $selectedAggregation) {
                    ForEach(AggregationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }
        case .container:
            Section {
                Text("Container will derive completion from its sub-activities.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .metric:
            Section {
                Picker("Tracking Method", selection: $selectedMetricKind) {
                    ForEach(MetricKind.allCases) { kind in
                        Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                    }
                }
                .onChange(of: selectedMetricKind) { _, newKind in
                    guard appearanceAutoSet else { return }
                    let suggestion = ActivityAppearance.suggest(
                        for: name, type: selectedType, metricKind: newKind
                    )
                    selectedIcon = suggestion.icon
                    selectedColor = suggestion.color
                }
                if selectedMetricKind == .value {
                    UnitPicker(selection: $unit)
                        .onChange(of: unit) { _, _ in
                            if !settingUnitFromSuggestion { unitAutoSet = false }
                        }
                }
            } header: {
                Text("Metric Configuration")
            } footer: {
                switch selectedMetricKind {
                case .photo: Text("Log progress photos each time you track.")
                case .value: Text("Log a numeric value each time you track.")
                case .checkbox: Text("Mark a milestone as achieved or not yet.")
                case .notes: Text("Write qualitative observations.")
                }
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
            .onChange(of: selectedCategory) { _, _ in
                guard !settingCategoryFromSuggestion else { return }
                categoryAutoSet = false
            }
            
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
                    Text("Reminder").tag(ScheduleMode.backlog)
                    Text("Reminder (Date)").tag(ScheduleMode.oneTime)
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
                    Text("Reminders sit in your list until marked done.")
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
            HStack(spacing: 8) {
                ForEach([TimeSlot.allDay, .morning, .afternoon, .evening], id: \.self) { slot in
                    let isSelected = slot == .allDay
                        ? (!isMultiSession && selectedSlot == .allDay)
                        : (isMultiSession ? selectedSlots.contains(slot) : selectedSlot == slot)

                    Button {
                        handleSlotTap(slot)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: slot.icon)
                                .font(.system(size: 14))
                            Text(slot.displayName)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if isMultiSession {
                Text("Activity repeats in \(selectedSlots.sorted().map(\.displayName).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func handleSlotTap(_ slot: TimeSlot) {
        if slot == .allDay {
            // All Day = clear multi-session, set to all day
            isMultiSession = false
            selectedSlot = .allDay
            selectedSlots.removeAll()
        } else if isMultiSession {
            // Already in multi-session mode
            if selectedSlots.contains(slot) {
                selectedSlots.remove(slot)
                if selectedSlots.count <= 1 {
                    // Dropped to 1 or 0 — go back to single mode
                    isMultiSession = false
                    selectedSlot = selectedSlots.first ?? .allDay
                    selectedSlots.removeAll()
                }
            } else {
                selectedSlots.insert(slot)
            }
        } else if selectedSlot == slot {
            // Tapping already-selected single slot — deselect → All Day
            selectedSlot = .allDay
        } else if selectedSlot != .allDay && selectedSlot != slot {
            // Second specific slot selected — enter multi-session mode
            isMultiSession = true
            selectedSlots = [selectedSlot, slot]
        } else {
            // Selecting first specific slot from All Day
            selectedSlot = slot
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
            HStack {
                Image(systemName: selectedIcon)
                    .font(.title2)
                    .foregroundStyle(Color(hex: selectedColor))
                    .frame(width: 44, height: 44)
                    .background(Color(hex: selectedColor).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Icon & Color")
                    if appearanceAutoSet {
                        Text("Auto-suggested from name")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            DisclosureGroup("Customize") {
                // Icon search
                TextField("Search icons…", text: $iconSearchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .autocorrectionDisabled()

                // Categorized icon grid
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(filteredIconCategories, id: \.name) { category in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(category.name.uppercased())
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(.tertiary)

                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                                    ForEach(category.icons, id: \.self) { icon in
                                        Button {
                                            selectedIcon = icon
                                            appearanceAutoSet = false
                                        } label: {
                                            Image(systemName: icon)
                                                .font(.system(size: 16))
                                                .frame(width: 36, height: 36)
                                                .background(selectedIcon == icon ? Color(hex: selectedColor).opacity(0.3) : Color(.tertiarySystemFill))
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                .foregroundStyle(selectedIcon == icon ? Color(hex: selectedColor) : .secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(colorOptions, id: \.self) { color in
                            Button {
                                selectedColor = color
                                appearanceAutoSet = false
                            } label: {
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
    }

    // MARK: - Advanced Integrations


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
            schedule = .daily
        } else {
            switch scheduleType {
            case .daily: schedule = .daily
            case .weekly: schedule = .weekly(Array(selectedWeekdays).sorted())
            case .monthly: schedule = .monthly(Array(selectedMonthDays).sorted())
            case .sticky: schedule = .sticky
            case .adhoc: schedule = .adhoc(adhocDate)
            }
        }

        if let activity = activityToEdit {
            if !activity.logs.isEmpty {
                pendingSchedule = schedule
                showEditScopeDialog = true
                return
            }
            performSave(activity: activity, schedule: schedule, futureOnly: false)
        } else {
            let activity = Activity(
                name: trimmed,
                icon: selectedIcon,
                hexColor: selectedColor,
                type: selectedType,
                schedule: schedule,
                timeWindow: selectedType != .container ? TimeWindow(slot: isMultiSession ? (selectedSlots.sorted().first ?? .morning) : selectedSlot) : nil,
                category: selectedCategory
            )

            if isMultiSession && selectedSlots.count > 1 {
                activity.timeSlots = selectedSlots.sorted()
            }

            if selectedType == .metric {
                activity.metricKind = selectedMetricKind
            }

            if selectedType == .value || selectedType == .cumulative || (selectedType == .metric && selectedMetricKind == .value) {
                activity.unit = unit.isEmpty ? nil : unit
            }
            if selectedType == .cumulative, let target = Double(targetValueText) {
                activity.targetValue = target
            }
            if selectedType == .cumulative {
                activity.aggregationMode = selectedAggregation
            }

            if isSubActivity, let parent = selectedParent {
                activity.parent = parent
            }

            if selectedType != .container && selectedType != .metric && enableHealthKit {
                activity.healthKitTypeID = hkType
                activity.healthKitModeRaw = hkMode
            }

            modelContext.insert(activity)
        }

        dismiss()
    }

    private func pauseTracking() {
        if let activity = activityToEdit {
            activity.stoppedAt = Date().startOfDay
            activity.pausedParentId = activity.parent?.id
            activity.parent = nil
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

    private func performSave(activity: Activity, schedule: Schedule, futureOnly: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        if futureOnly {
            let effectiveFrom = activity.configSnapshots
                .compactMap { $0.effectiveUntil }
                .max()
                .map { Calendar.current.date(byAdding: .day, value: 1, to: $0) ?? $0 }
                ?? activity.createdDate

            let snapshot = ActivityConfigSnapshot(
                activity: activity,
                effectiveFrom: effectiveFrom,
                effectiveUntil: Calendar.current.date(byAdding: .day, value: -1, to: Date().startOfDay) ?? Date().startOfDay
            )
            modelContext.insert(snapshot)
        }

        activity.name = trimmed
        activity.icon = selectedIcon
        activity.hexColor = selectedColor
        activity.type = selectedType
        activity.scheduleData = try? JSONEncoder().encode(schedule)
        activity.category = selectedCategory

        if selectedType == .metric {
            activity.metricKind = selectedMetricKind
        }

        if selectedType != .container {
            if isMultiSession && selectedSlots.count > 1 {
                let primarySlot = selectedSlots.sorted().first ?? .morning
                activity.timeWindowData = try? JSONEncoder().encode(TimeWindow(slot: primarySlot))
                activity.timeSlots = selectedSlots.sorted()
            } else {
                activity.timeWindowData = try? JSONEncoder().encode(TimeWindow(slot: selectedSlot))
                activity.timeSlotsData = nil
            }
        } else {
            activity.timeWindowData = nil
        }

        if selectedType == .value || selectedType == .cumulative || (selectedType == .metric && selectedMetricKind == .value) {
            activity.unit = unit.isEmpty ? nil : unit
        }
        if selectedType == .cumulative, let target = Double(targetValueText) {
            activity.targetValue = target
        }
        if selectedType == .cumulative {
            activity.aggregationMode = selectedAggregation
        }

        if isSubActivity, let parent = selectedParent {
            activity.parent = parent
        } else {
            activity.parent = nil
        }

        if selectedType != .container && selectedType != .metric && enableHealthKit {
            activity.healthKitTypeID = hkType
            activity.healthKitModeRaw = hkMode
        } else if selectedType == .container || selectedType == .metric {
            activity.healthKitTypeID = nil
            activity.healthKitModeRaw = nil
        }
    }
}

enum ScheduleMode {
    case recurring, oneTime, backlog
}
