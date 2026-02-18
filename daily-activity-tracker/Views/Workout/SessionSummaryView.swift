import SwiftUI
import SwiftData

/// Post-session summary showing duration, volume, per-exercise breakdown, and completion status.
struct SessionSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let session: StrengthSession

    private var sessionManager: StrengthSessionManager {
        StrengthSessionManager(modelContext: modelContext)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                completionBadge
                statsGrid
                exerciseBreakdown
                doneButton
            }
            .padding()
        }
        .navigationTitle("Session Complete")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: - Completion Badge

    private var completionBadge: some View {
        let ratio = sessionManager.completionRatio(for: session)
        let isComplete = ratio >= 0.8

        return VStack(spacing: 8) {
            Image(systemName: isComplete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(isComplete ? .green : .orange)

            Text(isComplete ? "Workout Complete!" : "Partial Workout")
                .font(.title3.weight(.bold))

            Text(String(format: "%.0f%% of planned sets", ratio * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        let volume = sessionManager.totalVolume(for: session)
        let completedSets = session.completedSets.count

        return HStack(spacing: 16) {
            statCard(title: "Duration", value: session.durationFormatted, icon: "timer")
            statCard(title: "Sets", value: "\(completedSets)", icon: "number")
            statCard(title: "Volume", value: formatVolume(volume), icon: "scalemass")
        }
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.orange)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Per-Exercise Breakdown

    private var exerciseBreakdown: some View {
        let grouped = sessionManager.setsGroupedByExercise(for: session)

        return VStack(alignment: .leading, spacing: 12) {
            Text("EXERCISE BREAKDOWN")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(grouped, id: \.exercise.id) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.exercise.displayName)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(item.sets.filter { !$0.isWarmup }.count) sets")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Set details
                    ForEach(item.sets) { setLog in
                        HStack(spacing: 8) {
                            Text(setLog.isWarmup ? "W" : "\(setLog.setNumber)")
                                .font(.caption2.monospacedDigit().weight(.medium))
                                .foregroundStyle(setLog.isWarmup ? .orange : .primary)
                                .frame(width: 18)

                            Text("\(setLog.reps) × \(String(format: "%.1f", setLog.weight))kg")
                                .font(.caption.monospacedDigit())

                            Spacer()

                            if let e1rm = setLog.estimated1RM {
                                Text("e1RM: \(String(format: "%.0f", e1rm))")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    // Best set highlight
                    if let bestSet = item.sets
                        .filter({ !$0.isWarmup })
                        .compactMap({ set in set.estimated1RM.map { (set: set, e1rm: $0) } })
                        .max(by: { $0.e1rm < $1.e1rm }) {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                            Text("Best: \(bestSet.set.reps) × \(String(format: "%.1f", bestSet.set.weight))kg (e1RM: \(String(format: "%.0f", bestSet.e1rm)))")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Done Button

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.orange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
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
