import SwiftUI
import SwiftData

/// Mon–Sun cardio plan editor — session type picker, multi-exercise per day, color linking.
struct CardioPlanEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var plan: WorkoutPlan

    @State private var dayForPicker: WorkoutPlanDay?
    @State private var dayForConfig: WorkoutPlanDay?

    private var planManager: WorkoutPlanManager {
        WorkoutPlanManager(modelContext: modelContext)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                planHeader
                weekGrid
                weeklyLoadSummary
                activateButton
            }
            .padding()
        }
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $dayForPicker) { day in
            NavigationStack {
                ExercisePickerView(exerciseType: .cardio) { exercise in
                    addExercise(exercise, to: day)
                }
            }
        }
        .sheet(item: $dayForConfig) { day in
            NavigationStack {
                CardioDayConfigSheet(day: day)
            }
        }
    }

    // MARK: - Header

    private var planHeader: some View {
        HStack {
            Image(systemName: "figure.run")
                .foregroundStyle(.green)
            Text(plan.name)
                .font(.headline)
            Spacer()
            statusBadge
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: plan.status.icon)
                .font(.caption2)
            Text(plan.status.displayName)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(plan.isActive ? Color.green.opacity(0.15) : Color(.systemGray5))
        .foregroundStyle(plan.isActive ? .green : .secondary)
        .clipShape(Capsule())
    }

    // MARK: - Multi-Row Week Grid (3 / 2 / 2)

    private var dayRows: [[WorkoutPlanDay]] {
        let days = plan.sortedDays
        guard days.count >= 7 else { return [days] }
        return [
            Array(days[0..<3]),
            Array(days[3..<5]),
            Array(days[5..<7])
        ]
    }

    private var weekGrid: some View {
        VStack(spacing: 10) {
            ForEach(Array(dayRows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(row) { day in
                        dayCard(day)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCard(_ day: WorkoutPlanDay) -> some View {
        VStack(spacing: 6) {
            // Header: weekday + color dot
            HStack(spacing: 4) {
                Text(day.weekdayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(day.colorEmoji)
                    .font(.caption2)
                    .onTapGesture { cycleColor(day) }
            }

            if day.isRest {
                // Compact rest day
                HStack(spacing: 4) {
                    Image(systemName: "bed.double.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("Rest")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            } else {
                // Expanded training day
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(day.sortedCardioExercises) { cardioEx in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(cardioEx.exercise?.name ?? "–")
                                .font(.system(size: 10).weight(.medium))
                                .lineLimit(1)
                            HStack(spacing: 3) {
                                Text(cardioEx.sessionType.displayName)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Text("·")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                Text(cardioEx.targetLabel)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    // Add + Configure buttons
                    HStack(spacing: 8) {
                        Button {
                            dayForPicker = day
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9))
                                Text("Add")
                                    .font(.system(size: 9))
                            }
                            .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)

                        if !day.cardioExercises.isEmpty {
                            Button {
                                dayForConfig = day
                            } label: {
                                HStack(spacing: 2) {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 9))
                                    Text("Config")
                                        .font(.system(size: 9))
                                }
                                .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Toggle rest/train
            Button {
                toggleRest(day)
            } label: {
                Text(day.isRest ? "Train" : "Rest")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Weekly Load

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

    // MARK: - Activate Button

    @ViewBuilder
    private var activateButton: some View {
        if plan.isDraft {
            Button {
                planManager.activatePlan(plan)
            } label: {
                Text("Activate Plan")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        } else if plan.isActive {
            Button(role: .destructive) {
                planManager.deactivatePlan(plan)
            } label: {
                Text("Deactivate Plan")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
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

    private func toggleRest(_ day: WorkoutPlanDay) {
        day.isRest.toggle()
        day.dayLabel = day.isRest ? "Rest" : ""
        try? modelContext.save()
    }

    private func cycleColor(_ day: WorkoutPlanDay) {
        if day.hasExercises && !day.isLinked { return }
        let next = (day.colorGroup + 2) % 8 - 1
        day.colorGroup = next
        try? modelContext.save()
    }
}

// MARK: - Cardio Day Config Sheet

struct CardioDayConfigSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var day: WorkoutPlanDay

    var body: some View {
        Form {
            ForEach(day.sortedCardioExercises) { cardioEx in
                Section(cardioEx.exercise?.displayName ?? "Exercise") {
                    // Session type
                    Picker("Session Type", selection: Binding(
                        get: { cardioEx.sessionType },
                        set: { cardioEx.sessionTypeRaw = $0.rawValue }
                    )) {
                        ForEach(CardioSessionType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    // Target: distance or duration
                    HStack {
                        Text("Target")
                        Spacer()
                        TextField("Distance", value: Binding(
                            get: { cardioEx.targetDistance ?? 0 },
                            set: { cardioEx.targetDistance = $0 > 0 ? $0 : nil }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        Text(cardioEx.exercise?.distanceUnit ?? "km")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Duration")
                        Spacer()
                        TextField("Min", value: Binding(
                            get: { cardioEx.targetDurationMin ?? 0 },
                            set: { cardioEx.targetDurationMin = $0 > 0 ? $0 : nil }
                        ), format: .number)
                        .keyboardType(.numberPad)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        Text("min")
                            .foregroundStyle(.secondary)
                    }

                    // Session type-specific params
                    sessionParamsSection(cardioEx)
                }
            }
        }
        .navigationTitle("\(day.weekdayFullName) Config")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private func sessionParamsSection(_ cardioEx: CardioPlanExercise) -> some View {
        switch cardioEx.sessionType {
        case .steadyState:
            Picker("HR Zone", selection: Binding(
                get: { cardioEx.steadyStateParams?.targetHRZone ?? 2 },
                set: { cardioEx.steadyStateParams = SteadyStateParams(targetHRZone: $0) }
            )) {
                ForEach(1...5, id: \.self) { zone in
                    Text("Zone \(zone)").tag(zone)
                }
            }

        case .hiit:
            let params = cardioEx.hiitParams ?? HIITParams(rounds: 8, workSeconds: 30, restSeconds: 60)
            Stepper("Rounds: \(params.rounds)", value: Binding(
                get: { params.rounds },
                set: { cardioEx.hiitParams = HIITParams(rounds: $0, workSeconds: params.workSeconds, restSeconds: params.restSeconds) }
            ), in: 1...30)
            Stepper("Work: \(params.workSeconds)s", value: Binding(
                get: { params.workSeconds },
                set: { cardioEx.hiitParams = HIITParams(rounds: params.rounds, workSeconds: $0, restSeconds: params.restSeconds) }
            ), in: 5...300, step: 5)
            Stepper("Rest: \(params.restSeconds)s", value: Binding(
                get: { params.restSeconds },
                set: { cardioEx.hiitParams = HIITParams(rounds: params.rounds, workSeconds: params.workSeconds, restSeconds: $0) }
            ), in: 5...300, step: 5)

        case .tempo:
            let params = cardioEx.tempoParams ?? TempoParams(warmupMin: 5, tempoMin: 20, cooldownMin: 5, targetHRZone: 3)
            Stepper("Warmup: \(params.warmupMin) min", value: Binding(
                get: { params.warmupMin },
                set: { cardioEx.tempoParams = TempoParams(warmupMin: $0, tempoMin: params.tempoMin, cooldownMin: params.cooldownMin, targetHRZone: params.targetHRZone) }
            ), in: 0...30)
            Stepper("Tempo: \(params.tempoMin) min", value: Binding(
                get: { params.tempoMin },
                set: { cardioEx.tempoParams = TempoParams(warmupMin: params.warmupMin, tempoMin: $0, cooldownMin: params.cooldownMin, targetHRZone: params.targetHRZone) }
            ), in: 5...60)
            Stepper("Cooldown: \(params.cooldownMin) min", value: Binding(
                get: { params.cooldownMin },
                set: { cardioEx.tempoParams = TempoParams(warmupMin: params.warmupMin, tempoMin: params.tempoMin, cooldownMin: $0, targetHRZone: params.targetHRZone) }
            ), in: 0...30)

        case .intervals:
            let params = cardioEx.intervalParams ?? IntervalParams(reps: 10, distancePerRep: 100, restSeconds: 60)
            Stepper("Reps: \(params.reps)", value: Binding(
                get: { params.reps },
                set: { cardioEx.intervalParams = IntervalParams(reps: $0, distancePerRep: params.distancePerRep, restSeconds: params.restSeconds) }
            ), in: 1...30)

        case .free:
            EmptyView()
        }
    }
}
