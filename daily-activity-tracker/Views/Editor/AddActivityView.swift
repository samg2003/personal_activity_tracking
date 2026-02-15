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
    @State private var scheduleType: ScheduleType = .daily
    @State private var selectedWeekdays: Set<Int> = []
    @State private var selectedSlot: TimeSlot = .morning
    @State private var selectedCategory: Category?

    // Value / Cumulative config
    @State private var targetValueText = ""
    @State private var unit = ""

    // Schedule config
    @State private var selectedMonthDays: Set<Int> = []
    @State private var adhocDate = Date()

    // Composable inputs
    @State private var allowsPhoto = false
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
        allActivities.filter { $0.type == .container }
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                typeSection
                typeSpecificSection
                categorySection
                scheduleSection
                timeWindowSection
                parentSection
                appearanceSection
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .navigationTitle("New Activity")
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
        }
    }

    // MARK: - Sections

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
        }
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            if selectedType != .container {
                Picker("Frequency", selection: $scheduleType) {
                    ForEach([ScheduleType.daily, .weekly, .monthly, .sticky, .adhoc], id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.menu)

                if scheduleType == .weekly {
                    weekdayPicker
                } else if scheduleType == .monthly {
                    monthlyPicker
                } else if scheduleType == .adhoc {
                    DatePicker("Date", selection: $adhocDate, displayedComponents: .date)
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
            Picker("When", selection: $selectedSlot) {
                ForEach([TimeSlot.allDay, .morning, .afternoon, .evening], id: \.self) { slot in
                    Label(slot.displayName, systemImage: slot.icon).tag(slot)
                }
            }
            .pickerStyle(.segmented)
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
                }
            }
        }
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
                Toggle(isOn: $allowsPhoto) {
                    Label("Photo Tracking", systemImage: "camera")
                }
                Toggle(isOn: $allowsNotes) {
                    Label("Notes", systemImage: "note.text")
                }
            }
        }
    }

    // MARK: - Advanced Integrations

    private var notificationsSection: some View {
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

    private var healthKitSection: some View {
        Section("HealthKit") {
            Toggle("Link to Health", isOn: $enableHealthKit)

            if enableHealthKit {
                Picker("Data Type", selection: $hkType) {
                    Text("Steps").tag("stepCount")
                    Text("Walking Check").tag("appleWalkingSteadiness") // dummy for now, needs proper mapping
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

        let activity = Activity(
            name: trimmed,
            icon: selectedIcon,
            hexColor: selectedColor,
            type: selectedType,
            schedule: schedule,
            timeWindow: TimeWindow(slot: selectedSlot),
            category: selectedCategory
        )
        
        activity.allowsPhoto = allowsPhoto
        activity.allowsNotes = allowsNotes

        // Configuration
        if selectedType == .value || selectedType == .cumulative {
            activity.unit = unit.isEmpty ? nil : unit
        }
        if selectedType == .cumulative, let target = Double(targetValueText) {
            activity.targetValue = target
        }

        // Parent
        if isSubActivity, let parent = selectedParent {
            activity.parent = parent
        }

        // Reminders
        if enableReminder {
            switch reminderType {
            case .time:
                let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                activity.reminder = .remindAt(hour: comps.hour ?? 9, minute: comps.minute ?? 0)
            case .morning:
                activity.reminder = .morningNudge
            case .evening:
                activity.reminder = .eveningCheckIn
            case .periodic:
                activity.reminder = .periodic(hours: periodicInterval)
            }
        } else {
            activity.reminder = .none
        }

        // HealthKit
        if enableHealthKit {
            activity.healthKitTypeID = hkType
            activity.healthKitModeRaw = hkMode
        }

        modelContext.insert(activity)
        dismiss()
    }
}

// Helper Enums for UI state
enum ReminderType: String, CaseIterable, Identifiable {
    case time, morning, evening, periodic
    var id: String { rawValue }
}
