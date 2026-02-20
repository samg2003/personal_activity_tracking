import SwiftUI
import SwiftData

/// Shared UI components used by both Strength and Cardio plan editors.
enum PlanEditorComponents {

    // MARK: - Week Strip

    /// Horizontal row of 7 tappable day pills. Long-press shows link color menu.
    struct WeekStrip: View {
        let days: [WorkoutPlanDay]
        @Binding var selectedIndex: Int
        var accentColor: Color = .orange
        let modelContext: ModelContext
        var onColorChange: ((WorkoutPlanDay) -> Void)? = nil
        var onLinkConflict: ((_ day: WorkoutPlanDay, _ newGroup: Int, _ existingDay: WorkoutPlanDay) -> Void)? = nil

        var body: some View {
            HStack(spacing: 5) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    DayPill(
                        day: day,
                        isSelected: index == selectedIndex,
                        accentColor: accentColor,
                        onTap: {
                            WDS.hapticSelection()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedIndex = index
                            }
                        },
                        colorMenu: {
                            colorMenuItems(for: day)
                        }
                    )
                }
            }
            .padding(.vertical, 4)
        }

        @ViewBuilder
        private func colorMenuItems(for day: WorkoutPlanDay) -> some View {
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

            if group >= 0 && day.hasExercises {
                let existingInGroup = days.first {
                    $0.id != day.id && $0.colorGroup == group && $0.hasExercises
                }
                if let existingDay = existingInGroup {
                    onLinkConflict?(day, group, existingDay)
                    return
                }
            }

            day.colorGroup = group
            try? modelContext.save()
            onColorChange?(day)
        }
    }

    /// Single day pill with premium styling — shadow on selected, spring animation.
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
            VStack(spacing: 3) {
                Text(day.weekdayName)
                    .font(.system(size: 11, weight: isSelected ? .heavy : .semibold))
                    .foregroundStyle(isSelected ? dayColor : .primary)

                if day.isRest {
                    Text("Rest")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                } else {
                    if !day.dayLabel.isEmpty {
                        Text(day.dayLabel)
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(isSelected ? dayColor : .secondary)
                    }
                    let count = day.totalSets > 0 ? "\(day.totalSets)s" :
                               !day.cardioExercises.isEmpty ? "\(day.cardioExercises.count)ex" : nil
                    if let count {
                        Text(count)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? dayColor.opacity(0.1) : pillFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? dayColor : .clear, lineWidth: 2)
            )
            .shadow(color: isSelected ? dayColor.opacity(0.2) : .clear, radius: 6, y: 2)
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .onTapGesture(perform: onTap)
            .contextMenu { colorMenu() }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }

        private var pillFill: Color {
            guard day.isLinked else { return Color(.systemGray6) }
            return dayColor.opacity(0.08)
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
                        WDS.hapticSelection()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
            HStack(spacing: 10) {
                IconBadge(icon: icon, color: accentColor, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.name)
                        .font(.title3.weight(.bold))
                    Text("\(plan.trainingDays.count) training days · \(plan.days.count - plan.trainingDays.count) rest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                PlanStatusBadge(plan: plan, accentColor: accentColor)
            }
        }
    }

    struct PlanStatusBadge: View {
        let plan: WorkoutPlan
        var accentColor: Color = .orange

        var body: some View {
            HStack(spacing: 4) {
                Circle()
                    .fill(plan.isActive ? .green : .secondary)
                    .frame(width: 6, height: 6)
                Text(plan.status.displayName)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(plan.isActive ? accentColor.opacity(0.2) : Color(.systemGray4), lineWidth: 0.5))
        }
    }

    // MARK: - Day Editor Header

    struct DayEditorHeader: View {
        let day: WorkoutPlanDay
        let subtitle: String?
        let onToggleRest: () -> Void

        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.weekdayFullName)
                        .font(.title3.weight(.bold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    WDS.hapticSelection()
                    onToggleRest()
                } label: {
                    Text(day.isRest ? "Train" : "Rest")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(day.isRest ? Color.green.opacity(0.12) : Color(.systemGray5))
                        .foregroundStyle(day.isRest ? .green : .secondary)
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accentColor)
                } else {
                    Text("No label")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.body)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Rest Day Content

    struct RestDayView: View {
        var body: some View {
            VStack(spacing: 8) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary.opacity(0.4))
                Text("Rest Day")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("Recovery is part of the plan")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Add Exercise Button

    struct AddExerciseButton: View {
        var accentColor: Color = .orange
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Exercise")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: WDS.buttonRadius, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                )
            }
            .buttonStyle(ScaleButtonStyle())
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
                GradientButton(
                    title: plan.isDraft ? "Activate Plan" : "Reactivate Plan",
                    icon: "bolt.fill",
                    gradient: accentColor == WDS.cardioAccent ? WDS.cardioGradient : WDS.strengthGradient
                ) {
                    onActivate()
                }
            } else if plan.isActive {
                Button(role: .destructive) {
                    WDS.hapticMedium()
                    onDeactivate()
                } label: {
                    Text("Deactivate Plan")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.red.opacity(0.8))
                }
            }
        }
    }

    // MARK: - Plan Editor Scaffold

    /// Shared editor structure used by both Strength and Cardio plan editors.
    struct PlanEditorScaffold<TrainingContent: View, ExtraSections: View>: View {
        @Environment(\.modelContext) private var modelContext
        @Bindable var plan: WorkoutPlan

        let icon: String
        let accentColor: Color
        let exerciseType: ExerciseType

        let excludedIDs: (WorkoutPlanDay) -> Set<UUID>
        let onAddExercise: (Exercise, WorkoutPlanDay) -> Void
        var autoLabelProvider: ((WorkoutPlanDay) -> String?)?

        @ViewBuilder let trainingContent: (_ day: WorkoutPlanDay, _ openPicker: @escaping () -> Void) -> TrainingContent
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
                VStack(spacing: 20) {
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
            .background(Color(.systemGroupedBackground))
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
            VStack(alignment: .leading, spacing: 14) {
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
            .premiumCard(accent: accentColor)
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
