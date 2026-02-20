import SwiftUI
import SwiftData

/// Post-session summary showing duration, volume, per-exercise breakdown, and completion status.
struct SessionSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let session: StrengthSession

    @State private var animateCheck = false

    private var sessionManager: StrengthSessionManager {
        StrengthSessionManager(modelContext: modelContext)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                completionBadge
                statsGrid
                exerciseBreakdown
                doneButton
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Session Complete")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.2)) {
                animateCheck = true
            }
        }
    }

    // MARK: - Completion Badge

    private var completionBadge: some View {
        let ratio = sessionManager.completionRatio(for: session)
        let isComplete = ratio >= 0.8

        return VStack(spacing: 10) {
            Image(systemName: isComplete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(isComplete ? .green : .orange)
                .scaleEffect(animateCheck ? 1.0 : 0.3)
                .opacity(animateCheck ? 1.0 : 0)

            Text(isComplete ? "Workout Complete!" : "Partial Workout")
                .font(.title3.weight(.bold))

            Text(String(format: "%.0f%% of planned sets", ratio * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        let volume = sessionManager.totalVolume(for: session)
        let completedSets = session.completedSets.count

        return HStack(spacing: 10) {
            MetricChip(icon: "timer", value: session.durationFormatted, label: "Duration", color: WDS.infoAccent)
            MetricChip(icon: "number", value: "\(completedSets)", label: "Sets", color: WDS.strengthAccent)
            MetricChip(icon: "scalemass", value: formatVolume(volume), label: "Volume", color: .purple)
        }
    }

    // MARK: - Exercise Breakdown

    private var exerciseBreakdown: some View {
        let grouped = sessionManager.setsGroupedByExercise(for: session)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Exercise Breakdown")
                .font(.headline)

            ForEach(grouped, id: \.exercise.id) { item in
                VStack(alignment: .leading, spacing: 8) {
                    // Exercise header
                    HStack {
                        Text(item.exercise.displayName)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(item.sets.filter { !$0.isWarmup }.count) sets")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    // Set details with zebra striping
                    VStack(spacing: 0) {
                        ForEach(Array(item.sets.enumerated()), id: \.element.id) { index, setLog in
                            HStack(spacing: 8) {
                                Text(setLog.isWarmup ? "W" : "\(setLog.setNumber)")
                                    .font(.caption2.monospacedDigit().weight(.bold))
                                    .foregroundStyle(setLog.isWarmup ? .orange : .primary)
                                    .frame(width: 18)

                                Text("\(setLog.reps) × \(String(format: "%.1f", setLog.weight))kg")
                                    .font(.caption.monospacedDigit())

                                Spacer()

                                if let e1rm = setLog.estimated1RM {
                                    Text("e1RM \(String(format: "%.0f", e1rm))")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(index % 2 == 0 ? Color(.systemGray6).opacity(0.5) : .clear)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    // Best set highlight
                    if let bestSet = item.sets
                        .filter({ !$0.isWarmup })
                        .compactMap({ set in set.estimated1RM.map { (set: set, e1rm: $0) } })
                        .max(by: { $0.e1rm < $1.e1rm }) {
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                            Text("Best: \(bestSet.set.reps) × \(String(format: "%.1f", bestSet.set.weight))kg")
                                .font(.caption.weight(.medium))
                            Text("(e1RM: \(String(format: "%.0f", bestSet.e1rm)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .premiumCard(accent: WDS.strengthAccent)
            }
        }
    }

    // MARK: - Done Button

    private var doneButton: some View {
        GradientButton(title: "Done", icon: "checkmark", gradient: WDS.strengthGradient) {
            dismiss()
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return String(format: "%.0f", volume)
    }
}
