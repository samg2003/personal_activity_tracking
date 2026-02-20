import SwiftUI
import SwiftData

/// Browse and search the exercise library — grouped by type, with premium styling.
struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var searchText = ""
    @State private var selectedType: ExerciseType?
    @State private var showingCreator = false
    @State private var selectedExercise: Exercise?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Filter chips
                filterBar
                    .padding(.horizontal)

                // Exercise cards
                LazyVStack(spacing: 10) {
                    ForEach(filteredExercises) { exercise in
                        Button {
                            WDS.hapticSelection()
                            selectedExercise = exercise
                        } label: {
                            ExerciseRowView(exercise: exercise)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .searchable(text: $searchText, prompt: "Search exercises…")
        .navigationTitle("Exercise Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreator = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3)
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

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("All", icon: "square.grid.2x2", isSelected: selectedType == nil) { selectedType = nil }
                filterChip("Strength", icon: "dumbbell.fill", isSelected: selectedType == .strength) { selectedType = .strength }
                filterChip("Cardio", icon: "figure.run", isSelected: selectedType == .cardio) { selectedType = .cardio }
                filterChip("Timed", icon: "timer", isSelected: selectedType == .timed) { selectedType = .timed }
            }
        }
    }

    private func filterChip(_ label: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            WDS.hapticSelection()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule().fill(chipGradient(for: label))
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .shadow(color: isSelected ? chipColor(for: label).opacity(0.3) : .clear, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func chipGradient(for label: String) -> LinearGradient {
        switch label {
        case "Strength": return WDS.strengthGradient
        case "Cardio": return WDS.cardioGradient
        default: return LinearGradient(colors: [.accentColor, .accentColor.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        }
    }

    private func chipColor(for label: String) -> Color {
        switch label {
        case "Strength": return WDS.strengthAccent
        case "Cardio": return WDS.cardioAccent
        default: return .accentColor
        }
    }

    // MARK: - Filtering

    private var filteredExercises: [Exercise] {
        exercises.filter { exercise in
            let matchesType = selectedType == nil || exercise.exerciseType == selectedType
            let matchesSearch = searchText.isEmpty ||
                exercise.searchableNames.contains { $0.localizedCaseInsensitiveContains(searchText) }
            return matchesType && matchesSearch
        }
    }
}

// MARK: - Exercise Row

struct ExerciseRowView: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            // Type icon badge
            IconBadge(icon: typeIcon, color: typeColor, size: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text(exercise.exerciseType.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(typeColor.opacity(0.12))
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(.quaternary)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 3, y: 1)
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
        case .strength: return WDS.strengthAccent
        case .cardio: return WDS.cardioAccent
        case .timed: return WDS.infoAccent
        }
    }
}
