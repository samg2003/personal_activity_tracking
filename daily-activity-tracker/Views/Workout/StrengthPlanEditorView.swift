import SwiftUI
import SwiftData

/// Mon–Sun strength plan editor — multi-row calendar, volume heatmap, junk alerts.
struct StrengthPlanEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var plan: WorkoutPlan

    @State private var dayForPicker: WorkoutPlanDay?
    @State private var showAdvancedVolume = false

    private var planManager: WorkoutPlanManager {
        WorkoutPlanManager(modelContext: modelContext)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                planHeader
                weekGrid
                volumeSection
                junkAlerts
                activateButton
            }
            .padding()
        }
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $dayForPicker) { day in
            NavigationStack {
                ExercisePickerView(exerciseType: .strength) { exercise in
                    addExercise(exercise, to: day)
                }
            }
        }
    }

    // MARK: - Header

    private var planHeader: some View {
        HStack {
            Image(systemName: "dumbbell.fill")
                .foregroundStyle(.orange)
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

    /// Lay out days in rows of 3, 2, 2 for comfortable sizing
    private var dayRows: [[WorkoutPlanDay]] {
        let days = plan.sortedDays
        guard days.count >= 7 else { return [days] }
        return [
            Array(days[0..<3]),  // Mon, Tue, Wed
            Array(days[3..<5]),  // Thu, Fri
            Array(days[5..<7])   // Sat, Sun
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
                    // Day label
                    if !day.dayLabel.isEmpty {
                        Text(day.dayLabel)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                    }

                    // Exercises
                    ForEach(day.sortedStrengthExercises) { planEx in
                        HStack(spacing: 2) {
                            Text(planEx.compactLabel)
                                .font(.system(size: 10))
                                .lineLimit(1)
                            Spacer()
                        }
                    }

                    // Add button
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Set count
                if day.totalSets > 0 {
                    Text("\(day.totalSets) sets")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
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

    // MARK: - Volume Section (Simple + Advanced)

    @ViewBuilder
    private var volumeSection: some View {
        let weeklyVolume = planManager.weeklyVolumePerMuscle(for: plan)
        if !weeklyVolume.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("WEEKLY VOLUME")
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
                let benchmarks = planManager.fetchMuscleBenchmarksPublic(name: group.parent)

                VStack(alignment: .leading, spacing: 4) {
                    // Parent header with range bar
                    HStack {
                        Text(group.parent)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text(String(format: "%.0f sets", parentSets))
                            .font(.caption.monospacedDigit())
                        Text(status.icon)
                            .font(.caption2)
                    }

                    // Range bar
                    GeometryReader { geo in
                        let maxVal = Double(max(benchmarks.mrv + 4, Int(parentSets) + 2))
                        let mevX = CGFloat(Double(benchmarks.mev) / maxVal) * geo.size.width
                        let mavX = CGFloat(Double(benchmarks.mav) / maxVal) * geo.size.width
                        let mrvX = CGFloat(Double(benchmarks.mrv) / maxVal) * geo.size.width
                        let currentX = CGFloat(min(parentSets, maxVal) / maxVal) * geo.size.width

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(.systemGray4))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.green.opacity(0.3))
                                .frame(width: max(0, mavX - mevX), height: 6)
                                .offset(x: mevX)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.yellow.opacity(0.3))
                                .frame(width: max(0, mrvX - mavX), height: 6)
                                .offset(x: mavX)
                            Circle()
                                .fill(colorForStatus(status))
                                .frame(width: 10, height: 10)
                                .offset(x: max(0, currentX - 5))
                        }
                    }
                    .frame(height: 10)

                    HStack {
                        Text("MEV \(benchmarks.mev)")
                        Spacer()
                        Text("MAV \(benchmarks.mav)")
                        Spacer()
                        Text("MRV \(benchmarks.mrv)")
                    }
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)

                    // Sub-muscles (only if there are actual children distinct from parent)
                    let realChildren = group.children.filter { $0.name != group.parent }
                    if !realChildren.isEmpty {
                        VStack(spacing: 2) {
                            ForEach(realChildren, id: \.name) { child in
                                HStack(spacing: 6) {
                                    Text("  ↳ \(child.name)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    ProgressView(value: min(child.sets, parentSets > 0 ? parentSets : 1), total: max(parentSets, 1))
                                        .tint(.orange.opacity(0.7))
                                        .frame(width: 60)
                                    Text(String(format: "%.1f", child.sets))
                                        .font(.system(size: 10).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, alignment: .trailing)
                                }
                            }
                        }
                        .padding(.leading, 4)
                    }
                }

                if group.parent != subMuscleData.last?.parent {
                    Divider()
                }
            }
        }
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
                    .background(Color.orange)
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
        let planEx = StrengthPlanExercise(
            exercise: exercise,
            targetSets: 3,
            rir: 2,
            sortOrder: day.strengthExercises.count
        )
        planEx.planDay = day
        modelContext.insert(planEx)

        // Auto-detect day label
        if !day.isLabelOverridden {
            day.dayLabel = planManager.autoDetectDayLabel(for: day)
        }

        planManager.propagateLinkedDays(from: day)
        try? modelContext.save()
    }

    private func toggleRest(_ day: WorkoutPlanDay) {
        day.isRest.toggle()
        if day.isRest {
            day.dayLabel = "Rest"
        } else if !day.isLabelOverridden {
            day.dayLabel = planManager.autoDetectDayLabel(for: day)
        }
        try? modelContext.save()
    }

    private func cycleColor(_ day: WorkoutPlanDay) {
        if day.hasExercises && !day.isLinked { return }
        let next = (day.colorGroup + 2) % 8 - 1
        day.colorGroup = next
        try? modelContext.save()
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
