import SwiftUI
import SwiftData

struct AddActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var name = ""
    @State private var selectedIcon = "circle"
    @State private var selectedColor = "#007AFF"
    @State private var selectedType: ActivityType = .checkbox
    @State private var scheduleType: ScheduleType = .daily
    @State private var selectedWeekdays: Set<Int> = []
    @State private var selectedSlot: TimeSlot = .morning
    @State private var selectedCategory: Category?

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

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                categorySection
                scheduleSection
                timeWindowSection
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

    private var nameSection: some View {
        Section {
            TextField("Activity name", text: $name)
                .font(.title3)
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
            Picker("Frequency", selection: $scheduleType) {
                ForEach([ScheduleType.daily, .weekly, .sticky], id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)

            if scheduleType == .weekly {
                weekdayPicker
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

    private var timeWindowSection: some View {
        Section("Time of Day") {
            Picker("When", selection: $selectedSlot) {
                ForEach([TimeSlot.morning, .afternoon, .evening], id: \.self) { slot in
                    Label(slot.displayName, systemImage: slot.icon).tag(slot)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            // Icon picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(iconOptions, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                        } label: {
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

            // Color picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(colorOptions, id: \.self) { color in
                        Button {
                            selectedColor = color
                        } label: {
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if selectedColor == color {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                            .fontWeight(.bold)
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

    // MARK: - Save

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let schedule: Schedule
        switch scheduleType {
        case .daily: schedule = .daily
        case .weekly: schedule = .weekly(Array(selectedWeekdays).sorted())
        case .sticky: schedule = .sticky
        default: schedule = .daily
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

        modelContext.insert(activity)
        dismiss()
    }
}
