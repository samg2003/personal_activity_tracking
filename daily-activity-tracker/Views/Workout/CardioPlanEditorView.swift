import SwiftUI
import SwiftData

/// Mon–Sun cardio plan editor — week strip + swipable day detail, matching strength editor layout.
struct CardioPlanEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var plan: WorkoutPlan

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
                PlanEditorComponents.PlanHeader(plan: plan, icon: "figure.run", accentColor: .green)

                PlanEditorComponents.WeekStrip(
                    days: sortedDays,
                    selectedIndex: $selectedDayIndex,
                    accentColor: .green,
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

                weeklyLoadSummary

                PlanEditorComponents.ActivateButton(
                    plan: plan,
                    accentColor: .green,
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
                    exerciseType: .cardio,
                    excludedExerciseIDs: Set(day.sortedCardioExercises.compactMap { $0.exercise?.id })
                ) { exercise in
                    addExercise(exercise, to: day)
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

    /// Resolves a link conflict by setting the color group, mirroring from the keep day.
    private func resolveLinkConflict(keepDay: WorkoutPlanDay, discardDay: WorkoutPlanDay) {
        guard let day = conflictDay else { return }
        day.colorGroup = conflictNewGroup
        try? modelContext.save()
        planManager.propagateLinkedDays(from: keepDay)
    }

    // MARK: - Day Detail (Swipable)

    private var dayDetail: some View {
        PlanEditorComponents.SwipableDayContainer(
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
            PlanEditorComponents.DayEditorHeader(
                day: day,
                subtitle: day.isRest ? nil : (!day.cardioExercises.isEmpty ? "\(day.cardioExercises.count) exercises" : nil),
                onToggleRest: { toggleRest(day) }
            )

            if day.isRest {
                PlanEditorComponents.RestDayView()
            } else {
                cardioDayContent(day)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Cardio Day Content

    @ViewBuilder
    private func cardioDayContent(_ day: WorkoutPlanDay) -> some View {
        // Day label
        PlanEditorComponents.DayLabelRow(day: day, accentColor: .green) {
            editLabelText = day.dayLabel
            editingDayLabel = day
            showLabelEditor = true
        }

        // Exercise cards
        ForEach(day.sortedCardioExercises) { cardioEx in
            cardioExerciseCard(cardioEx, day: day)
        }

        // Add exercise
        PlanEditorComponents.AddExerciseButton(accentColor: .green) {
            dayForPicker = day
        }
    }

    // MARK: - Cardio Exercise Card

    private func cardioExerciseCard(_ cardioEx: CardioPlanExercise, day: WorkoutPlanDay) -> some View {
        VStack(spacing: 8) {
            // Name + session type + delete
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cardioEx.exercise?.name ?? "Unknown")
                        .font(.subheadline.weight(.medium))
                    Text(cardioEx.sessionType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Target label
                Text(cardioEx.targetLabel)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.1))
                    .clipShape(Capsule())

                Button(role: .destructive) {
                    deleteExercise(cardioEx, from: day)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            // Session type picker
            HStack(spacing: 12) {
                Text("Type")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: Binding(
                    get: { cardioEx.sessionType },
                    set: {
                        cardioEx.sessionTypeRaw = $0.rawValue
                        savePlanChange(day)
                    }
                )) {
                    ForEach(CardioSessionType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Target inputs
            HStack(spacing: 12) {
                // Distance
                HStack(spacing: 4) {
                    Text("Dist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("—", value: Binding(
                        get: { cardioEx.targetDistance ?? 0 },
                        set: {
                            cardioEx.targetDistance = $0 > 0 ? $0 : nil
                            savePlanChange(day)
                        }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 55)
                    Text(cardioEx.exercise?.distanceUnit ?? "km")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Duration
                HStack(spacing: 4) {
                    Text("Dur")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("—", value: Binding(
                        get: { cardioEx.targetDurationMin ?? 0 },
                        set: {
                            cardioEx.targetDurationMin = $0 > 0 ? $0 : nil
                            savePlanChange(day)
                        }
                    ), format: .number)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 55)
                    Text("min")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Weekly Load Summary

    @ViewBuilder
    private var weeklyLoadSummary: some View {
        let sessions = plan.trainingDays.count
        let totalExercises = plan.trainingDays.reduce(0) { $0 + $1.cardioExercises.count }

        if sessions > 0 {
            HStack(spacing: 16) {
                loadPill("\(sessions)", label: "sessions")
                loadPill("\(totalExercises)", label: "exercises")
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func loadPill(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.green)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func addExercise(_ exercise: Exercise, to day: WorkoutPlanDay) {
        let cardioEx = CardioPlanExercise(
            exercise: exercise,
            sessionType: .free,
            sortOrder: day.cardioExercises.count
        )
        cardioEx.planDay = day
        modelContext.insert(cardioEx)
        day.isRest = false
        if day.dayLabel.isEmpty || day.dayLabel == "Rest" {
            day.dayLabel = exercise.name
        }
        planManager.propagateLinkedDays(from: day)
        try? modelContext.save()
    }

    private func deleteExercise(_ cardioEx: CardioPlanExercise, from day: WorkoutPlanDay) {
        modelContext.delete(cardioEx)
        try? modelContext.save()
        planManager.propagateLinkedDays(from: day)
    }

    private func savePlanChange(_ day: WorkoutPlanDay) {
        try? modelContext.save()
        planManager.propagateLinkedDays(from: day)
    }

    private func toggleRest(_ day: WorkoutPlanDay) {
        day.isRest.toggle()
        day.dayLabel = day.isRest ? "Rest" : ""
        try? modelContext.save()
        if plan.isActive {
            planManager.syncShellActivities(for: plan)
        }
    }
}
