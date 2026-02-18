import SwiftUI
import SwiftData

/// View/edit exercise details — muscle involvements, cardio config, aliases.
struct ExerciseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var exercise: Exercise
    @Query(sort: \MuscleGroup.sortOrder) private var allMuscles: [MuscleGroup]

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Name", value: exercise.name)
                LabeledContent("Equipment", value: exercise.equipment)
                LabeledContent("Type", value: exercise.exerciseType.displayName)
            }

            if !exercise.aliases.isEmpty {
                Section("Aliases") {
                    ForEach(exercise.aliases, id: \.self) { alias in
                        Text(alias)
                    }
                }
            }

            if exercise.exerciseType == .strength || exercise.exerciseType == .timed {
                Section("Muscle Involvements") {
                    if exercise.muscleInvolvements.isEmpty {
                        Text("No muscles configured")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(exercise.muscleInvolvements) { involvement in
                            HStack {
                                Text(muscleNameFor(involvement))
                                Spacer()
                                // Visual bar
                                ProgressView(value: involvement.involvementScore, total: 1.0)
                                    .frame(width: 60)
                                    .tint(involvementColor(involvement.involvementScore))
                                Text(String(format: "%.0f%%", involvement.involvementScore * 100))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                    }
                }
            }

            if exercise.exerciseType == .cardio {
                Section("Cardio Config") {
                    if let unit = exercise.distanceUnit {
                        LabeledContent("Distance Unit", value: unit)
                    }
                    if let unit = exercise.paceUnit {
                        LabeledContent("Pace Unit", value: unit)
                    }
                    if !exercise.availableMetrics.isEmpty {
                        LabeledContent("Metrics") {
                            Text(exercise.availableMetrics.map(\.displayName).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let notes = exercise.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }
        }
        .navigationTitle(exercise.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func muscleNameFor(_ involvement: ExerciseMuscle) -> String {
        guard let muscleID = involvement.muscleGroupID else { return "Unknown" }
        return allMuscles.first { $0.id == muscleID }?.name ?? "Unknown"
    }

    private func involvementColor(_ score: Double) -> Color {
        if score >= 0.7 { return .red }
        if score >= 0.4 { return .orange }
        return .yellow
    }
}
