import SwiftUI
import SwiftData

/// Shared UI components used by both Strength and Cardio plan editors.
enum PlanEditorComponents {

    // MARK: - Week Strip

    /// Horizontal row of 7 tappable day pills. Long-press cycles color group.
    struct WeekStrip: View {
        let days: [WorkoutPlanDay]
        @Binding var selectedIndex: Int
        var accentColor: Color = .orange
        let modelContext: ModelContext
        /// Called after a color change that does NOT conflict (no exercises to resolve).
        var onColorChange: ((WorkoutPlanDay) -> Void)? = nil
        /// Called when linking would merge two days that both have exercises.
        /// Parameters: (day being changed, new colorGroup, existing day in that group)
        var onLinkConflict: ((_ day: WorkoutPlanDay, _ newGroup: Int, _ existingDay: WorkoutPlanDay) -> Void)? = nil

        var body: some View {
            HStack(spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    DayPill(
                        day: day,
                        isSelected: index == selectedIndex,
                        accentColor: accentColor,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedIndex = index
                            }
                        },
                        colorMenu: {
                            colorMenuItems(for: day)
                        }
                    )
                }
            }
        }

        @ViewBuilder
        private func colorMenuItems(for day: WorkoutPlanDay) -> some View {
            // Color choices
            ForEach(0..<WorkoutPlanDay.linkColors.count, id: \.self) { group in
                let color = WorkoutPlanDay.linkColors[group]
                Button {
                    setColor(day, group: group)
                } label: {
                    Label {
                        Text(color.name)
                    } icon: {
                        Text(color.emoji)
                    }
                }
                .disabled(day.colorGroup == group)
            }

            Divider()

            Button(role: .destructive) {
                setColor(day, group: -1)
            } label: {
                Label("Unlink", systemImage: "link.badge.plus")
            }
            .disabled(!day.isLinked)
        }

        private func setColor(_ day: WorkoutPlanDay, group: Int) {
            let oldGroup = day.colorGroup

            // Check for conflict: day has exercises AND target group already has days with exercises
            if group >= 0 && day.hasExercises {
                let existingInGroup = days.first {
                    $0.id != day.id && $0.colorGroup == group && $0.hasExercises
                }
                if let existingDay = existingInGroup {
                    // Conflict: let the parent handle it
                    onLinkConflict?(day, group, existingDay)
                    return
                }
            }

            day.colorGroup = group
            try? modelContext.save()
            onColorChange?(day)
        }
    }

    /// Single day pill in the week strip.
    /// - Tap: selects this day in the detail view
    /// - Long-press: shows context menu with link color options
    /// - Selected: hollow outline with the day's link color (or accent)
    /// - Non-selected linked: filled background tint
    struct DayPill<Menu: View>: View {
        let day: WorkoutPlanDay
        let isSelected: Bool
        var accentColor: Color = .orange
        let onTap: () -> Void
        @ViewBuilder var colorMenu: () -> Menu

        private var dayColor: Color {
            guard day.isLinked, day.colorGroup >= 0, day.colorGroup < WorkoutPlanDay.linkColors.count else {
                return accentColor
            }
            return Self.linkColor(day.colorGroup)
        }

        var body: some View {
            VStack(spacing: 2) {
                Text(day.weekdayName)
                    .font(.system(size: 11, weight: .semibold))

                if day.isRest {
                    Text("Rest")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                } else {
                    if !day.dayLabel.isEmpty {
                        Text(day.dayLabel)
                            .font(.system(size: 9))
                            .lineLimit(1)
                    }
                    let count = day.totalSets > 0 ? "\(day.totalSets)s" :
                               !day.cardioExercises.isEmpty ? "\(day.cardioExercises.count)ex" : nil
                    if let count {
                        Text(count)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.clear : pillFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? dayColor : .clear, lineWidth: 2)
            )
            .onTapGesture(perform: onTap)
            .contextMenu { colorMenu() }
        }

        /// Non-selected: linked days get a tinted fill, unlinked get gray.
        private var pillFill: Color {
            guard day.isLinked else { return Color(.systemGray6) }
            return dayColor.opacity(0.12)
        }

        static func linkColor(_ group: Int) -> Color {
            switch group {
            case 0: return .red
            case 1: return .orange
            case 2: return .yellow
            case 3: return .green
            case 4: return .blue
            case 5: return .purple
            case 6: return .gray
            default: return .gray
            }
        }
    }

    // MARK: - Swipable Day Container

    /// Container that renders a single day's content with swipe-to-navigate gesture.
    struct SwipableDayContainer<Content: View>: View {
        @Binding var selectedIndex: Int
        let dayCount: Int
        @ViewBuilder var content: () -> Content

        var body: some View {
            Group {
                content()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
                    .id(selectedIndex)
            }
            .gesture(
                DragGesture(minimumDistance: 50)
                    .onEnded { value in
                        let horizontal = value.translation.width
                        guard abs(horizontal) > abs(value.translation.height) else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if horizontal < 0, selectedIndex < dayCount - 1 {
                                selectedIndex += 1
                            } else if horizontal > 0, selectedIndex > 0 {
                                selectedIndex -= 1
                            }
                        }
                    }
            )
        }
    }

    // MARK: - Plan Header

    struct PlanHeader: View {
        let plan: WorkoutPlan
        let icon: String
        var accentColor: Color = .orange

        var body: some View {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(accentColor)
                Text(plan.name)
                    .font(.headline)
                Spacer()
                StatusBadge(plan: plan, accentColor: accentColor)
            }
        }
    }

    struct StatusBadge: View {
        let plan: WorkoutPlan
        var accentColor: Color = .orange

        var body: some View {
            HStack(spacing: 4) {
                Image(systemName: plan.status.icon)
                    .font(.caption2)
                Text(plan.status.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(plan.isActive ? accentColor.opacity(0.15) : Color(.systemGray5))
            .foregroundStyle(plan.isActive ? accentColor : .secondary)
            .clipShape(Capsule())
        }
    }

    // MARK: - Day Editor Header

    struct DayEditorHeader: View {
        let day: WorkoutPlanDay
        let subtitle: String?
        let onToggleRest: () -> Void

        var body: some View {
            HStack {
                Text(day.weekdayFullName)
                    .font(.title3.weight(.semibold))

                if let subtitle {
                    Text("· \(subtitle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onToggleRest) {
                    Text(day.isRest ? "Train" : "Rest")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Day Label Row

    struct DayLabelRow: View {
        let day: WorkoutPlanDay
        var accentColor: Color = .orange
        let onEdit: () -> Void

        var body: some View {
            HStack {
                if !day.dayLabel.isEmpty {
                    Text(day.dayLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(accentColor)
                } else {
                    Text("No label")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Rest Day Content

    struct RestDayView: View {
        var body: some View {
            HStack {
                Image(systemName: "bed.double.fill")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("Rest Day")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Add Exercise Button

    struct AddExerciseButton: View {
        var accentColor: Color = .orange
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Exercise")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Activate / Deactivate

    struct ActivateButton: View {
        let plan: WorkoutPlan
        var accentColor: Color = .orange
        let onActivate: () -> Void
        let onDeactivate: () -> Void

        var body: some View {
            if plan.isDraft || plan.isInactive {
                Button(action: onActivate) {
                    Text(plan.isDraft ? "Activate Plan" : "Reactivate Plan")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else if plan.isActive {
                Button(role: .destructive, action: onDeactivate) {
                    Text("Deactivate Plan")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - Plan Editor Scaffold

    /// Shared editor structure used by both Strength and Cardio plan editors.
    /// Each editor provides its unique content via closures, while the scaffold
    /// handles all shared state, navigation, and modifiers.
    struct PlanEditorScaffold<TrainingContent: View, ExtraSections: View>: View {
        @Environment(\.modelContext) private var modelContext
        @Bindable var plan: WorkoutPlan

        let icon: String
        let accentColor: Color
        let exerciseType: ExerciseType

        /// Provides the exercise IDs to exclude from the picker for a given day.
        let excludedIDs: (WorkoutPlanDay) -> Set<UUID>
        /// Called when user picks an exercise from the sheet.
        let onAddExercise: (Exercise, WorkoutPlanDay) -> Void
        /// Returns an auto-detected label for non-rest days (strength uses muscle detection, cardio returns nil).
        var autoLabelProvider: ((WorkoutPlanDay) -> String?)?

        /// Builds the training day content (exercise cards + add button). Receives an `openPicker` action to trigger the exercise picker sheet.
        @ViewBuilder let trainingContent: (_ day: WorkoutPlanDay, _ openPicker: @escaping () -> Void) -> TrainingContent
        /// Extra sections below the day detail (volume, junk alerts, weekly load, etc.).
        @ViewBuilder let extraSections: () -> ExtraSections

        @State private var selectedDayIndex: Int = 0
        @State private var dayForPicker: WorkoutPlanDay?
        @State private var editLabelText: String = ""
        @State private var editingDayLabel: WorkoutPlanDay?
        @State private var showLabelEditor = false

        // Link conflict resolution
        @State private var showLinkConflict = false
        @State private var conflictDay: WorkoutPlanDay?
        @State private var conflictNewGroup: Int = -1
        @State private var conflictExistingDay: WorkoutPlanDay?

        private var planManager: WorkoutPlanManager {
            WorkoutPlanManager(modelContext: modelContext)
        }

        private var sortedDays: [WorkoutPlanDay] {
            plan.days.sorted { $0.weekday < $1.weekday }
        }

        var body: some View {
            ScrollView {
                VStack(spacing: 16) {
                    PlanHeader(plan: plan, icon: icon, accentColor: accentColor)

                    WeekStrip(
                        days: sortedDays,
                        selectedIndex: $selectedDayIndex,
                        accentColor: accentColor,
                        modelContext: modelContext,
                        onColorChange: { day in
                            planManager.propagateLinkedDays(from: day)
                        },
                        onLinkConflict: { day, newGroup, existingDay in
                            conflictDay = day
                            conflictNewGroup = newGroup
                            conflictExistingDay = existingDay
                            showLinkConflict = true
                        }
                    )

                    dayDetail

                    extraSections()

                    ActivateButton(
                        plan: plan,
                        accentColor: accentColor,
                        onActivate: { planManager.activatePlan(plan) },
                        onDeactivate: { planManager.deactivatePlan(plan) }
                    )
                }
                .padding()
            }
            .navigationTitle(plan.name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $dayForPicker) { day in
                NavigationStack {
                    ExercisePickerView(
                        exerciseType: exerciseType,
                        excludedExerciseIDs: excludedIDs(day)
                    ) { exercise in
                        onAddExercise(exercise, day)
                    }
                }
            }
            .renameDayAlert(
                isPresented: $showLabelEditor,
                labelText: $editLabelText,
                day: editingDayLabel,
                modelContext: modelContext,
                planManager: planManager
            )
            .alert("Link Conflict", isPresented: $showLinkConflict) {
                if let conflictDay, let conflictExistingDay {
                    Button("Keep \(conflictDay.weekdayName)'s exercises") {
                        resolveLinkConflict(keepDay: conflictDay, discardDay: conflictExistingDay)
                    }
                    Button("Keep \(conflictExistingDay.weekdayName)'s exercises") {
                        resolveLinkConflict(keepDay: conflictExistingDay, discardDay: conflictDay)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Both days have exercises. Which day's exercises should be kept? The other day's exercises will be replaced.")
            }
        }

        // MARK: - Day Detail

        private var dayDetail: some View {
            SwipableDayContainer(
                selectedIndex: $selectedDayIndex,
                dayCount: sortedDays.count
            ) {
                if selectedDayIndex < sortedDays.count {
                    dayEditorContent(sortedDays[selectedDayIndex])
                }
            }
        }

        @ViewBuilder
        private func dayEditorContent(_ day: WorkoutPlanDay) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                DayEditorHeader(
                    day: day,
                    subtitle: daySummary(day),
                    onToggleRest: { toggleRest(day) }
                )

                if day.isRest {
                    RestDayView()
                } else {
                    DayLabelRow(day: day, accentColor: accentColor) {
                        editLabelText = day.dayLabel
                        editingDayLabel = day
                        showLabelEditor = true
                    }

                    trainingContent(day, { dayForPicker = day })
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        // MARK: - Actions

        private func toggleRest(_ day: WorkoutPlanDay) {
            day.isRest.toggle()
            if day.isRest {
                day.dayLabel = "Rest"
            } else if !day.isLabelOverridden {
                day.dayLabel = autoLabelProvider?(day) ?? ""
            }
            try? modelContext.save()
            if plan.isActive {
                planManager.syncShellActivities(for: plan)
            }
        }

        private func resolveLinkConflict(keepDay: WorkoutPlanDay, discardDay: WorkoutPlanDay) {
            guard let day = conflictDay else { return }
            day.colorGroup = conflictNewGroup
            try? modelContext.save()
            planManager.propagateLinkedDays(from: keepDay)
        }

        /// Generates the subtitle for the day editor header.
        private func daySummary(_ day: WorkoutPlanDay) -> String? {
            guard !day.isRest else { return nil }
            if day.totalSets > 0 { return "\(day.totalSets) sets" }
            if !day.cardioExercises.isEmpty { return "\(day.cardioExercises.count) exercises" }
            return nil
        }
    }

    // MARK: - Rename Alert Modifier

    struct RenameDayModifier: ViewModifier {
        @Binding var isPresented: Bool
        @Binding var labelText: String
        let day: WorkoutPlanDay?
        let modelContext: ModelContext
        let planManager: WorkoutPlanManager

        func body(content: Content) -> some View {
            content
                .alert("Rename Day", isPresented: $isPresented) {
                    TextField("Label", text: $labelText)
                    Button("Save") {
                        if let day {
                            day.dayLabel = labelText
                            day.isLabelOverridden = true
                            try? modelContext.save()
                        }
                    }
                    Button("Reset to Auto") {
                        if let day {
                            day.isLabelOverridden = false
                            day.dayLabel = planManager.autoDetectDayLabel(for: day)
                            try? modelContext.save()
                        }
                    }
                    Button("Cancel", role: .cancel) { }
                }
        }
    }
}

extension View {
    func renameDayAlert(
        isPresented: Binding<Bool>,
        labelText: Binding<String>,
        day: WorkoutPlanDay?,
        modelContext: ModelContext,
        planManager: WorkoutPlanManager
    ) -> some View {
        modifier(PlanEditorComponents.RenameDayModifier(
            isPresented: isPresented,
            labelText: labelText,
            day: day,
            modelContext: modelContext,
            planManager: planManager
        ))
    }
}
