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
            accentColor: WDS.strengthAccent,
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

        PlanEditorComponents.AddExerciseButton(accentColor: WDS.strengthAccent, action: openPicker)
    }

    // MARK: - Exercise Card

    private func exerciseCard(_ planEx: StrengthPlanExercise, day: WorkoutPlanDay) -> some View {
        VStack(spacing: 10) {
            // Header: name + equipment + delete
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(planEx.exercise?.name ?? "Unknown")
                        .font(.subheadline.weight(.semibold))
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
                    Image(systemName: "trash.circle.fill")
                        .font(.body)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.red.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            // Sets + RIR steppers
            HStack(spacing: 16) {
                stepperRow("Sets", value: planEx.targetSets, range: 1...10) { newVal in
                    planEx.targetSets = newVal
                    savePlanChange(day)
                }

                Spacer()

                stepperRow("RIR", value: planEx.rir, range: 0...5) { newVal in
                    planEx.rir = newVal
                    savePlanChange(day)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    /// Reusable stepper with pill-shaped increment/decrement buttons.
    private func stepperRow(_ label: String, value: Int, range: ClosedRange<Int>, onChange: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)

            Button {
                if value > range.lowerBound {
                    WDS.hapticLight()
                    onChange(value - 1)
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(value > range.lowerBound ? 1.0 : 0.3)

            Text("\(value)")
                .font(.body.weight(.bold).monospacedDigit())
                .frame(width: 26, alignment: .center)

            Button {
                if value < range.upperBound {
                    WDS.hapticLight()
                    onChange(value + 1)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(value < range.upperBound ? 1.0 : 0.3)
        }
    }

    // MARK: - Volume Section

    @ViewBuilder
    private var volumeSection: some View {
        let weeklyVolume = planManager.weeklyVolumePerMuscle(for: plan)
        if !weeklyVolume.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Weekly Volume")
                        .font(.headline)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showAdvancedVolume.toggle()
                        }
                    } label: {
                        Text(showAdvancedVolume ? "Simple" : "Advanced")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if showAdvancedVolume {
                    advancedVolumeView(weeklyVolume)
                } else {
                    simpleVolumeView(weeklyVolume)
                }
            }
            .premiumCard(accent: WDS.strengthAccent)
        }
    }

    private func simpleVolumeView(_ weeklyVolume: [String: Double]) -> some View {
        VStack(spacing: 6) {
            ForEach(weeklyVolume.sorted(by: { $0.key < $1.key }), id: \.key) { muscle, sets in
                let status = planManager.volumeStatus(muscle: muscle, effectiveSets: sets)
                HStack(spacing: 8) {
                    Text(muscle)
                        .font(.caption.weight(.medium))
                        .frame(width: 75, alignment: .leading)

                    GeometryReader { geo in
                        let fraction = min(sets / 25.0, 1.0)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color(.systemGray5))
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(volumeGradient(for: status))
                                .frame(width: geo.size.width * fraction)
                        }
                        .frame(height: 6)
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 14)

                    Text(String(format: "%.0f", sets))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .frame(width: 24, alignment: .trailing)

                    Text(status.icon)
                        .font(.caption2)
                }
            }
        }
    }

    private func advancedVolumeView(_ weeklyVolume: [String: Double]) -> some View {
        let subMuscleData = planManager.weeklyVolumePerSubMuscle(for: plan)

        return VStack(spacing: 12) {
            // Legend
            HStack(spacing: 10) {
                legendDot("Below MEV", color: .red)
                legendDot("Near MEV", color: .yellow)
                legendDot("In MAV", color: .green)
                legendDot("Above MRV", color: .red.opacity(0.6))
            }
            .font(.system(size: 9, weight: .medium))
            .padding(.bottom, 2)

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
                            .font(.caption.weight(.medium).monospacedDigit())
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
                                        .frame(width: 5, height: 5)
                                    Text(child.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(String(format: "%.1f", child.sets))
                                        .font(.caption.weight(.medium).monospacedDigit())
                                        .foregroundStyle(colorForStatus(childStatus))
                                        .frame(width: 32, alignment: .trailing)
                                }
                            }
                        }
                        .padding(.leading, 16)
                    }
                }

                if group.parent != subMuscleData.last?.parent {
                    Divider().padding(.vertical, 2)
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
            VStack(alignment: .leading, spacing: 6) {
                ForEach(alerts) { alert in
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("\(alert.muscle) \(alert.dayLabel): \(String(format: "%.0f", alert.effectiveSets)) eff. sets (MRV=\(alert.mrv))")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .premiumCard(accent: .orange, padding: 12)
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

    private func volumeGradient(for status: VolumeStatus) -> LinearGradient {
        let color = colorForStatus(status)
        return LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing)
    }
}
