import SwiftUI
import SwiftData

/// Browse and search the exercise library — grouped by type.
struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var searchText = ""
    @State private var selectedType: ExerciseType?
    @State private var showingCreator = false
    @State private var selectedExercise: Exercise?

    var body: some View {
        List {
            // Type filter chips
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip("All", isSelected: selectedType == nil) { selectedType = nil }
                        filterChip("Strength", isSelected: selectedType == .strength) { selectedType = .strength }
                        filterChip("Cardio", isSelected: selectedType == .cardio) { selectedType = .cardio }
                        filterChip("Timed", isSelected: selectedType == .timed) { selectedType = .timed }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listRowBackground(Color.clear)

            // Exercise list
            ForEach(filteredExercises) { exercise in
                Button {
                    selectedExercise = exercise
                } label: {
                    ExerciseRowView(exercise: exercise)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search exercises…")
        .navigationTitle("Exercise Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreator = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showingCreator) {
            NavigationStack {
                ExerciseCreatorView()
            }
        }
        .sheet(item: $selectedExercise) { exercise in
            NavigationStack {
                ExerciseDetailView(exercise: exercise)
            }
        }
    }

    private var filteredExercises: [Exercise] {
        exercises.filter { exercise in
            let matchesType = selectedType == nil || exercise.exerciseType == selectedType
            let matchesSearch = searchText.isEmpty ||
                exercise.searchableNames.contains { $0.localizedCaseInsensitiveContains(searchText) }
            return matchesType && matchesSearch
        }
    }

    private func filterChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Exercise Row

struct ExerciseRowView: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: typeIcon)
                .font(.title3)
                .foregroundStyle(typeColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.displayName)
                    .font(.body)

                HStack(spacing: 6) {
                    Text(exercise.exerciseType.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(typeColor.opacity(0.15))
                        .foregroundStyle(typeColor)
                        .clipShape(Capsule())

                    if !exercise.aliases.isEmpty {
                        Text("+\(exercise.aliases.count) alias\(exercise.aliases.count == 1 ? "" : "es")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if exercise.exerciseType == .strength {
                        let muscleCount = exercise.muscleInvolvements.count
                        if muscleCount > 0 {
                            Text("\(muscleCount) muscle\(muscleCount == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var typeIcon: String {
        switch exercise.exerciseType {
        case .strength: return "dumbbell.fill"
        case .cardio: return "figure.run"
        case .timed: return "timer"
        }
    }

    private var typeColor: Color {
        switch exercise.exerciseType {
        case .strength: return .orange
        case .cardio: return .green
        case .timed: return .blue
        }
    }
}
