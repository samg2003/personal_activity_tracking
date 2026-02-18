import SwiftUI
import SwiftData

/// 3-tier exercise picker: inline search → library browser → create new.
/// Used by plan editors when adding exercises to a day.
struct ExercisePickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    let exerciseType: ExerciseType  // Filter: .strength or .cardio
    let onSelect: (Exercise) -> Void

    @State private var searchText = ""
    @State private var showingCreator = false

    var body: some View {
        List {
            // Quick search results
            if !searchText.isEmpty {
                Section("Results") {
                    if matchingExercises.isEmpty {
                        Button {
                            showingCreator = true
                        } label: {
                            Label("Create \"\(searchText)\"…", systemImage: "plus.circle")
                                .foregroundStyle(Color.accentColor)
                        }
                    } else {
                        ForEach(matchingExercises) { exercise in
                            Button { select(exercise) } label: {
                                ExerciseRowView(exercise: exercise)
                            }
                        }
                    }
                }
            }

            // Browse all
            Section(searchText.isEmpty ? "All \(exerciseType.displayName) Exercises" : "All") {
                ForEach(typeFilteredExercises) { exercise in
                    Button { select(exercise) } label: {
                        ExerciseRowView(exercise: exercise)
                    }
                }
            }

            // Create new
            Section {
                Button {
                    showingCreator = true
                } label: {
                    Label("Create New Exercise", systemImage: "plus.circle.fill")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search exercises…")
        .navigationTitle("Pick Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .sheet(isPresented: $showingCreator) {
            NavigationStack {
                ExerciseCreatorView()
            }
        }
    }

    private var typeFilteredExercises: [Exercise] {
        exercises.filter { $0.exerciseType == exerciseType }
    }

    private var matchingExercises: [Exercise] {
        typeFilteredExercises.filter { exercise in
            exercise.searchableNames.contains {
                $0.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private func select(_ exercise: Exercise) {
        onSelect(exercise)
        dismiss()
    }
}
