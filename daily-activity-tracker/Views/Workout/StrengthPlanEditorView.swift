import SwiftUI
import SwiftData

/// Strength plan editor — uses shared scaffold + strength-specific exercise cards and volume analysis.
struct StrengthPlanEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var plan: WorkoutPlan

    @State private var showAdvancedVolume = false

    private var planManager: WorkoutPlanManager {
        WorkoutPlanManager(modelContext: modelContext)
    }

    var body: some View {
        PlanEditorComponents.PlanEditorScaffold(
            plan: plan,
            icon: "dumbbell.fill",
            accentColor: .orange,
            exerciseType: .strength,
            excludedIDs: { day in
                Set(day.sortedStrengthExercises.compactMap { $0.exercise?.id })
            },
            onAddExercise: { exercise, day in
                addExercise(exercise, to: day)
            },
            autoLabelProvider: { day in
                planManager.autoDetectDayLabel(for: day)
            },
            trainingContent: { day, openPicker in
                trainingDayContent(day, openPicker: openPicker)
            },
            extraSections: {
                volumeSection
                junkAlerts
            }
        )
    }

    // MARK: - Training Day Content

    @ViewBuilder
    private func trainingDayContent(_ day: WorkoutPlanDay, openPicker: @escaping () -> Void) -> some View {
        ForEach(day.sortedStrengthExercises) { planEx in
            exerciseCard(planEx, day: day)
        }

        PlanEditorComponents.AddExerciseButton(accentColor: .orange, action: openPicker)
    }

    // MARK: - Exercise Card

    private func exerciseCard(_ planEx: StrengthPlanExercise, day: WorkoutPlanDay) -> some View {
        VStack(spacing: 8) {
            // Name + equipment + delete
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(planEx.exercise?.name ?? "Unknown")
                        .font(.subheadline.weight(.medium))
                    if let equipment = planEx.exercise?.equipment, !equipment.isEmpty {
                        Text(equipment)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    deleteExercise(planEx, from: day)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            // Sets + RIR steppers
            HStack(spacing: 16) {
                // Sets
                HStack(spacing: 8) {
                    Text("Sets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 0) {
                        Button {
                            if planEx.targetSets > 1 {
                                planEx.targetSets -= 1
                                savePlanChange(day)
                            }
                        } label: {
                            Image(systemName: "minus")
                                .font(.caption.weight(.semibold))
                                .frame(width: 28, height: 28)
                                .background(Color(.systemGray5))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Text("\(planEx.targetSets)")
                            .font(.body.weight(.semibold).monospacedDigit())
                            .frame(width: 30)

                        Button {
                            if planEx.targetSets < 10 {
                                planEx.targetSets += 1
                                savePlanChange(day)
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.caption.weight(.semibold))
                                .frame(width: 28, height: 28)
                                .background(Color(.systemGray5))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                // RIR
                HStack(spacing: 8) {
                    Text("RIR")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 0) {
                        Button {
                            if planEx.rir > 0 {
                                planEx.rir -= 1
                                savePlanChange(day)
                            }
                        } label: {
                            Image(systemName: "minus")
                                .font(.caption.weight(.semibold))
                                .frame(width: 28, height: 28)
                                .background(Color(.systemGray5))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Text("\(planEx.rir)")
                            .font(.body.weight(.semibold).monospacedDigit())
                            .frame(width: 30)

                        Button {
                            if planEx.rir < 5 {
                                planEx.rir += 1
                                savePlanChange(day)
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.caption.weight(.semibold))
                                .frame(width: 28, height: 28)
                                .background(Color(.systemGray5))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Volume Section

    @ViewBuilder
    private var volumeSection: some View {
        let weeklyVolume = planManager.weeklyVolumePerMuscle(for: plan)
        if !weeklyVolume.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Weekly Volume")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(showAdvancedVolume ? "Simple" : "Advanced") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAdvancedVolume.toggle()
                        }
                    }
                    .font(.caption)
                }

                if showAdvancedVolume {
                    advancedVolumeView(weeklyVolume)
                } else {
                    simpleVolumeView(weeklyVolume)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func simpleVolumeView(_ weeklyVolume: [String: Double]) -> some View {
        ForEach(weeklyVolume.sorted(by: { $0.key < $1.key }), id: \.key) { muscle, sets in
            let status = planManager.volumeStatus(muscle: muscle, effectiveSets: sets)
            HStack(spacing: 8) {
                Text(muscle)
                    .font(.caption)
                    .frame(width: 70, alignment: .leading)
                ProgressView(value: min(sets, 25), total: 25)
                    .tint(colorForStatus(status))
                Text(String(format: "%.0f", sets))
                    .font(.caption.monospacedDigit())
                    .frame(width: 24, alignment: .trailing)
                Text(status.icon)
                    .font(.caption2)
            }
        }
    }

    private func advancedVolumeView(_ weeklyVolume: [String: Double]) -> some View {
        let subMuscleData = planManager.weeklyVolumePerSubMuscle(for: plan)

        return VStack(spacing: 10) {
            // Legend
            HStack(spacing: 12) {
                legendDot("Below MEV", color: .red)
                legendDot("Near MEV", color: .yellow)
                legendDot("In MAV", color: .green)
                legendDot("Above MRV", color: .red.opacity(0.6))
            }
            .font(.system(size: 9))
            .padding(.bottom, 4)

            ForEach(subMuscleData, id: \.parent) { group in
                let parentSets = weeklyVolume[group.parent] ?? 0
                let status = planManager.volumeStatus(muscle: group.parent, effectiveSets: parentSets)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(colorForStatus(status))
                            .frame(width: 8, height: 8)
                        Text(group.parent)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(String(format: "%.0f sets", parentSets))
                            .font(.caption.monospacedDigit())
                        Text(status.icon)
                            .font(.caption2)
                    }

                    let realChildren = group.children.filter { $0.name != group.parent }
                    if !realChildren.isEmpty {
                        VStack(spacing: 3) {
                            ForEach(realChildren, id: \.name) { child in
                                let childStatus = subMuscleStatus(child: child, parentSets: parentSets, parentMuscle: group.parent)
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(colorForStatus(childStatus))
                                        .frame(width: 6, height: 6)
                                    Text(child.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(String(format: "%.1f", child.sets))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(colorForStatus(childStatus))
                                        .frame(width: 32, alignment: .trailing)
                                }
                            }
                        }
                        .padding(.leading, 16)
                    }
                }

                if group.parent != subMuscleData.last?.parent {
                    Divider()
                }
            }
        }
    }

    private func subMuscleStatus(child: (name: String, sets: Double), parentSets: Double, parentMuscle: String) -> VolumeStatus {
        guard parentSets > 0 else { return .belowMEV }
        let ratio = child.sets / parentSets
        let benchmarks = planManager.fetchMuscleBenchmarksPublic(name: parentMuscle)
        let scaledSets = ratio * parentSets
        let scaledMev = Double(benchmarks.mev) * ratio
        let scaledMav = Double(benchmarks.mav) * ratio
        let scaledMrv = Double(benchmarks.mrv) * ratio
        if scaledSets < scaledMev { return .belowMEV }
        if scaledSets < scaledMav { return .nearMEV }
        if scaledSets <= scaledMrv { return .inMAV }
        return .aboveMRV
    }

    private func legendDot(_ label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
        }
    }

    // MARK: - Junk Alerts

    @ViewBuilder
    private var junkAlerts: some View {
        let alerts = planManager.junkVolumeAlerts(for: plan)
        if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(alerts) { alert in
                    HStack(spacing: 4) {
                        Text("⚠️")
                        Text("\(alert.muscle) \(alert.dayLabel): \(String(format: "%.0f", alert.effectiveSets)) eff. sets (MRV=\(alert.mrv))")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func addExercise(_ exercise: Exercise, to day: WorkoutPlanDay) {
        let planEx = StrengthPlanExercise(
            exercise: exercise,
            targetSets: 3,
            rir: 2,
            sortOrder: day.strengthExercises.count
        )
        planEx.planDay = day
        modelContext.insert(planEx)

        if !day.isLabelOverridden {
            day.dayLabel = planManager.autoDetectDayLabel(for: day)
        }

        planManager.propagateLinkedDays(from: day)
        try? modelContext.save()
    }

    private func deleteExercise(_ planEx: StrengthPlanExercise, from day: WorkoutPlanDay) {
        modelContext.delete(planEx)
        try? modelContext.save()

        if !day.isLabelOverridden {
            day.dayLabel = planManager.autoDetectDayLabel(for: day)
        }
        planManager.propagateLinkedDays(from: day)
    }

    private func savePlanChange(_ day: WorkoutPlanDay) {
        try? modelContext.save()
        planManager.propagateLinkedDays(from: day)
    }

    private func colorForStatus(_ status: VolumeStatus) -> Color {
        switch status {
        case .belowMEV: return .red
        case .nearMEV: return .yellow
        case .inMAV: return .green
        case .aboveMRV: return .red
        }
    }
}
