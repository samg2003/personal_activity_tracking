import SwiftUI
import SwiftData

/// Create a new exercise — muscle involvement sliders (strength) or cardio config.
struct ExerciseCreatorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MuscleGroup.sortOrder) private var allMuscles: [MuscleGroup]

    @State private var name = ""
    @State private var equipment = ""
    @State private var exerciseType: ExerciseType = .strength
    @State private var aliasesText = ""
    @State private var notes = ""
    @State private var videoURLsText = ""

    // Strength
    @State private var muscleScores: [UUID: Double] = [:]

    // Cardio
    @State private var distanceUnit = "km"
    @State private var paceUnit = "min/km"
    @State private var selectedMetrics: Set<CardioMetric> = []

    private var parentMuscles: [MuscleGroup] {
        allMuscles.filter { $0.isParent }
    }

    private var childMuscles: [MuscleGroup] {
        allMuscles.filter { !$0.isParent }
    }

    var body: some View {
        Form {
            // Basic info
            Section("Exercise Info") {
                TextField("Name (e.g. Bench Press)", text: $name)
                TextField("Equipment (e.g. Barbell)", text: $equipment)

                Picker("Type", selection: $exerciseType) {
                    ForEach(ExerciseType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
            }

            Section("Aliases (one per line)") {
                TextEditor(text: $aliasesText)
                    .frame(minHeight: 60)
            }

            // Muscle involvements (strength / timed)
            if exerciseType == .strength || exerciseType == .timed {
                Section("Muscle Involvements") {
                    ForEach(parentMuscles) { parent in
                        VStack(alignment: .leading, spacing: 4) {
                            muscleSlider(muscle: parent)

                            // Show children indented
                            let children = childMuscles.filter { $0.parentID == parent.id }
                            if !children.isEmpty {
                                ForEach(children) { child in
                                    muscleSlider(muscle: child, indent: true)
                                }
                            }
                        }
                    }
                }
            }

            // Cardio config
            if exerciseType == .cardio {
                Section("Cardio Config") {
                    Picker("Distance Unit", selection: $distanceUnit) {
                        Text("km").tag("km")
                        Text("miles").tag("miles")
                        Text("meters").tag("m")
                        Text("yards").tag("yards")
                    }

                    Picker("Pace Unit", selection: $paceUnit) {
                        Text("min/km").tag("min/km")
                        Text("min/mile").tag("min/mile")
                        Text("/100m").tag("/100m")
                        Text("/500m").tag("/500m")
                        Text("km/h").tag("km/h")
                    }
                }

                Section("Available Metrics") {
                    ForEach(CardioMetric.allCases) { metric in
                        Toggle(isOn: Binding(
                            get: { selectedMetrics.contains(metric) },
                            set: { selected in
                                if selected { selectedMetrics.insert(metric) }
                                else { selectedMetrics.remove(metric) }
                            }
                        )) {
                            Label(metric.displayName, systemImage: metric.icon)
                        }
                    }
                }
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 60)
            }

            Section("Video URLs (one per line)") {
                TextEditor(text: $videoURLsText)
                    .frame(minHeight: 60)
                    .autocapitalization(.none)
                    .font(.body.monospaced())
                Text("YouTube links will be embedded inline")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .navigationTitle("New Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(name.isEmpty || equipment.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func muscleSlider(muscle: MuscleGroup, indent: Bool = false) -> some View {
        let score = muscleScores[muscle.id] ?? 0
        HStack {
            if indent { Spacer().frame(width: 16) }
            Text(muscle.name)
                .font(indent ? .caption : .body)
                .foregroundStyle(indent ? .secondary : .primary)
            Spacer()
            Slider(value: Binding(
                get: { muscleScores[muscle.id] ?? 0 },
                set: { muscleScores[muscle.id] = $0 }
            ), in: 0...1, step: 0.1)
            .frame(width: 120)
            Text(score > 0 ? String(format: "%.0f%%", score * 100) : "–")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private func save() {
        let exercise = Exercise(name: name, equipment: equipment, type: exerciseType, isPreSeeded: false)

        let aliases = aliasesText.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        exercise.aliases = aliases
        exercise.notes = notes.isEmpty ? nil : notes
        let urls = videoURLsText.split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        exercise.videoURLs = urls

        modelContext.insert(exercise)

        // Muscle involvements
        if exerciseType == .strength || exerciseType == .timed {
            for (muscleID, score) in muscleScores where score > 0 {
                let involvement = ExerciseMuscle(muscleGroupID: muscleID, score: score)
                involvement.exercise = exercise
                modelContext.insert(involvement)
            }
        }

        // Cardio
        if exerciseType == .cardio {
            exercise.distanceUnit = distanceUnit
            exercise.paceUnit = paceUnit
            exercise.availableMetrics = Array(selectedMetrics)
        }

        try? modelContext.save()
        dismiss()
    }
}
