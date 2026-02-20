import SwiftUI
import SwiftData

/// 3-tier exercise picker: inline search → library browser → create new.
/// Uses premium styling with material rows and haptic feedback.
struct ExercisePickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    let exerciseType: ExerciseType
    var excludedExerciseIDs: Set<UUID> = []
    let onSelect: (Exercise) -> Void

    @State private var searchText = ""
    @State private var showingCreator = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Quick search results
                if !searchText.isEmpty {
                    if matchingExercises.isEmpty {
                        Button {
                            showingCreator = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(WDS.cardioAccent)
                                Text("Create \"\(searchText)\"…")
                                    .font(.subheadline.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .padding(.horizontal)
                    } else {
                        LazyVStack(spacing: 8) {
                            SectionTitle(title: "Results", trailing: "\(matchingExercises.count) found")
                                .padding(.horizontal)
                            ForEach(matchingExercises) { exercise in
                                Button {
                                    WDS.hapticSelection()
                                    select(exercise)
                                } label: {
                                    ExerciseRowView(exercise: exercise)
                                }
                                .buttonStyle(ScaleButtonStyle())
                                .padding(.horizontal)
                            }
                        }
                    }
                }

                // Browse all
                LazyVStack(spacing: 8) {
                    SectionTitle(
                        title: searchText.isEmpty ? "All \(exerciseType.displayName)" : "All",
                        trailing: "\(typeFilteredExercises.count)"
                    )
                    .padding(.horizontal)

                    ForEach(typeFilteredExercises) { exercise in
                        Button {
                            WDS.hapticSelection()
                            select(exercise)
                        } label: {
                            ExerciseRowView(exercise: exercise)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .padding(.horizontal)
                    }
                }

                // Create new
                Button {
                    showingCreator = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                        Text("Create New Exercise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(WDS.strengthAccent)
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(WDS.strengthAccent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
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
        exercises.filter { $0.exerciseType == exerciseType && !excludedExerciseIDs.contains($0.id) }
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
