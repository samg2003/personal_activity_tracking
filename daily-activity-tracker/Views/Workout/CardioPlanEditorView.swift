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
            accentColor: WDS.cardioAccent,
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

        PlanEditorComponents.AddExerciseButton(accentColor: WDS.cardioAccent, action: openPicker)
    }

    // MARK: - Cardio Exercise Card

    private func cardioExerciseCard(_ cardioEx: CardioPlanExercise, day: WorkoutPlanDay) -> some View {
        VStack(spacing: 10) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cardioEx.exercise?.name ?? "Unknown")
                        .font(.subheadline.weight(.semibold))
                    Text(cardioEx.sessionType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(cardioEx.targetLabel)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(WDS.cardioAccent.opacity(0.1))
                    .clipShape(Capsule())
                    .foregroundStyle(WDS.cardioAccent)

                Button {
                    deleteExercise(cardioEx, from: day)
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.body)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.red.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            // Session type picker — styled segmented
            HStack(spacing: 10) {
                Text("Type")
                    .font(.caption.weight(.medium))
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

            // Type-specific parameter editors
            typeSpecificInputs(cardioEx, day: day)

            // Shared target inputs (distance + duration)
            HStack(spacing: 16) {
                targetInput(
                    label: "Distance",
                    unit: cardioEx.exercise?.distanceUnit ?? "km",
                    value: Binding(
                        get: { cardioEx.targetDistance ?? 0 },
                        set: {
                            cardioEx.targetDistance = $0 > 0 ? $0 : nil
                            savePlanChange(day)
                        }
                    )
                )

                targetInput(
                    label: "Duration",
                    unit: "min",
                    value: Binding(
                        get: { Double(cardioEx.targetDurationMin ?? 0) },
                        set: {
                            cardioEx.targetDurationMin = $0 > 0 ? Int($0) : nil
                            savePlanChange(day)
                        }
                    )
                )
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    private func targetInput(label: String, unit: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
            HStack(spacing: 4) {
                TextField("—", value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .font(.subheadline.monospacedDigit())
                Text(unit)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Type-Specific Parameter Editors

    @ViewBuilder
    private func typeSpecificInputs(_ cardioEx: CardioPlanExercise, day: WorkoutPlanDay) -> some View {
        switch cardioEx.sessionType {
        case .steadyState:
            let params = cardioEx.steadyStateParams ?? SteadyStateParams(targetHRZone: 2)
            VStack(alignment: .leading, spacing: 6) {
                Text("Target HR Zone")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                Picker("HR Zone", selection: Binding(
                    get: { params.targetHRZone },
                    set: {
                        cardioEx.steadyStateParams = SteadyStateParams(targetHRZone: $0)
                        savePlanChange(day)
                    }
                )) {
                    ForEach(1...5, id: \.self) { zone in
                        Text("Z\(zone)").tag(zone)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(10)
            .background(WDS.cardioAccent.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .hiit:
            let params = cardioEx.hiitParams ?? HIITParams(rounds: 8, workSeconds: 30, restSeconds: 15)
            VStack(spacing: 6) {
                paramStepper("Rounds", value: params.rounds, range: 1...30, icon: "repeat") {
                    cardioEx.hiitParams = HIITParams(rounds: $0, workSeconds: params.workSeconds, restSeconds: params.restSeconds)
                    savePlanChange(day)
                }
                paramStepper("Work", value: params.workSeconds, range: 5...300, step: 5, unit: "sec", icon: "flame.fill") {
                    cardioEx.hiitParams = HIITParams(rounds: params.rounds, workSeconds: $0, restSeconds: params.restSeconds)
                    savePlanChange(day)
                }
                paramStepper("Rest", value: params.restSeconds, range: 5...300, step: 5, unit: "sec", icon: "pause.circle") {
                    cardioEx.hiitParams = HIITParams(rounds: params.rounds, workSeconds: params.workSeconds, restSeconds: $0)
                    savePlanChange(day)
                }
            }
            .padding(10)
            .background(WDS.cardioAccent.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .tempo:
            let params = cardioEx.tempoParams ?? TempoParams(warmupMin: 5, tempoMin: 20, cooldownMin: 5, targetHRZone: 3)
            VStack(spacing: 6) {
                paramStepper("Warmup", value: params.warmupMin, range: 0...30, unit: "min", icon: "sun.max.fill") {
                    cardioEx.tempoParams = TempoParams(warmupMin: $0, tempoMin: params.tempoMin, cooldownMin: params.cooldownMin, targetHRZone: params.targetHRZone)
                    savePlanChange(day)
                }
                paramStepper("Tempo", value: params.tempoMin, range: 1...90, unit: "min", icon: "bolt.fill") {
                    cardioEx.tempoParams = TempoParams(warmupMin: params.warmupMin, tempoMin: $0, cooldownMin: params.cooldownMin, targetHRZone: params.targetHRZone)
                    savePlanChange(day)
                }
                paramStepper("Cooldown", value: params.cooldownMin, range: 0...30, unit: "min", icon: "snowflake") {
                    cardioEx.tempoParams = TempoParams(warmupMin: params.warmupMin, tempoMin: params.tempoMin, cooldownMin: $0, targetHRZone: params.targetHRZone)
                    savePlanChange(day)
                }
                HStack {
                    Text("Tempo HR Zone")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { params.targetHRZone },
                        set: {
                            cardioEx.tempoParams = TempoParams(warmupMin: params.warmupMin, tempoMin: params.tempoMin, cooldownMin: params.cooldownMin, targetHRZone: $0)
                            savePlanChange(day)
                        }
                    )) {
                        ForEach(1...5, id: \.self) { z in Text("Z\(z)").tag(z) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                }
            }
            .padding(10)
            .background(WDS.cardioAccent.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .intervals:
            let params = cardioEx.intervalParams ?? IntervalParams(reps: 6, distancePerRep: 400, restSeconds: 90)
            VStack(spacing: 6) {
                paramStepper("Reps", value: params.reps, range: 1...30, icon: "arrow.clockwise") {
                    cardioEx.intervalParams = IntervalParams(reps: $0, distancePerRep: params.distancePerRep, restSeconds: params.restSeconds)
                    savePlanChange(day)
                }
                HStack(spacing: 8) {
                    Text("Distance/rep")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    TextField("—", value: Binding(
                        get: { params.distancePerRep },
                        set: {
                            cardioEx.intervalParams = IntervalParams(reps: params.reps, distancePerRep: $0, restSeconds: params.restSeconds)
                            savePlanChange(day)
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .font(.subheadline.monospacedDigit())
                    Text(cardioEx.exercise?.distanceUnit ?? "m")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                paramStepper("Rest", value: params.restSeconds, range: 10...600, step: 10, unit: "sec", icon: "pause.circle") {
                    cardioEx.intervalParams = IntervalParams(reps: params.reps, distancePerRep: params.distancePerRep, restSeconds: $0)
                    savePlanChange(day)
                }
            }
            .padding(10)
            .background(WDS.cardioAccent.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .free:
            EmptyView()
        }
    }

    /// Reusable integer stepper row for type-specific params
    private func paramStepper(
        _ label: String,
        value: Int,
        range: ClosedRange<Int>,
        step: Int = 1,
        unit: String? = nil,
        icon: String,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(WDS.cardioAccent)
                .frame(width: 16)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
            Spacer()

            Button {
                WDS.hapticLight()
                let newVal = max(range.lowerBound, value - step)
                onChange(newVal)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(WDS.cardioAccent)
            }
            .buttonStyle(.plain)
            .disabled(value <= range.lowerBound)

            Text("\(value)\(unit.map { " \($0)" } ?? "")")
                .font(.subheadline.monospacedDigit().weight(.medium))
                .frame(minWidth: 50)
                .multilineTextAlignment(.center)

            Button {
                WDS.hapticLight()
                let newVal = min(range.upperBound, value + step)
                onChange(newVal)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(WDS.cardioAccent)
            }
            .buttonStyle(.plain)
            .disabled(value >= range.upperBound)
        }
    }

    // MARK: - Weekly Load Summary

    @ViewBuilder
    private var weeklyLoadSummary: some View {
        let sessions = plan.trainingDays.count
        let totalExercises = plan.trainingDays.reduce(0) { $0 + $1.cardioExercises.count }

        if totalExercises > 0 {
            HStack(spacing: 12) {
                MetricChip(
                    icon: "calendar",
                    value: "\(sessions)",
                    label: "Sessions/wk",
                    color: WDS.cardioAccent
                )
                MetricChip(
                    icon: "figure.run",
                    value: "\(totalExercises)",
                    label: "Exercises/wk",
                    color: WDS.cardioAccent
                )
            }
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
