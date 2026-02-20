import SwiftUI
import SwiftData

/// Cardio plan editor — uses shared scaffold + cardio-specific exercise cards and weekly load summary.
struct CardioPlanEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var plan: WorkoutPlan

    private var planManager: WorkoutPlanManager {
        WorkoutPlanManager(modelContext: modelContext)
    }

    var body: some View {
        PlanEditorComponents.PlanEditorScaffold(
            plan: plan,
            icon: "figure.run",
            accentColor: .green,
            exerciseType: .cardio,
            excludedIDs: { day in
                Set(day.sortedCardioExercises.compactMap { $0.exercise?.id })
            },
            onAddExercise: { exercise, day in
                addExercise(exercise, to: day)
            },
            trainingContent: { day, openPicker in
                trainingDayContent(day, openPicker: openPicker)
            },
            extraSections: {
                weeklyLoadSummary
            }
        )
    }

    // MARK: - Training Day Content

    @ViewBuilder
    private func trainingDayContent(_ day: WorkoutPlanDay, openPicker: @escaping () -> Void) -> some View {
        ForEach(day.sortedCardioExercises) { cardioEx in
            cardioExerciseCard(cardioEx, day: day)
        }

        PlanEditorComponents.AddExerciseButton(accentColor: .green, action: openPicker)
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
                    .foregroundStyle(.secondary)

                Button {
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
                        get: { cardioEx.targetDuration ?? 0 },
                        set: {
                            cardioEx.targetDuration = $0 > 0 ? $0 : nil
                            savePlanChange(day)
                        }
                    ), format: .number)
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

        if totalExercises > 0 {
            HStack(spacing: 20) {
                loadStat("\(sessions)", label: "Sessions/wk")
                loadStat("\(totalExercises)", label: "Exercises/wk")
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func loadStat(_ value: String, label: String) -> some View {
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
}
