import SwiftUI
import SwiftData

/// Main Workout Tab — today's workout, plans, quick links, recent sessions.
struct WorkoutTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutPlan.createdAt, order: .reverse) private var allPlans: [WorkoutPlan]
    @Query(sort: \StrengthSession.date, order: .reverse) private var recentStrength: [StrengthSession]
    @Query(sort: \CardioSession.date, order: .reverse) private var recentCardio: [CardioSession]

    @State private var showingNewPlan = false
    @State private var newPlanType: ExerciseType = .strength

    private var planManager: WorkoutPlanManager {
        WorkoutPlanManager(modelContext: modelContext)
    }

    private var visiblePlans: [WorkoutPlan] {
        allPlans.filter { $0.status != .inactive }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    todaySection
                    myPlansSection
                    quickLinksSection
                    recentSessionsSection
                }
                .padding()
            }
            .navigationTitle("Workouts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            newPlanType = .strength
                            showingNewPlan = true
                        } label: {
                            Label("New Strength Plan", systemImage: "dumbbell.fill")
                        }
                        Button {
                            newPlanType = .cardio
                            showingNewPlan = true
                        } label: {
                            Label("New Cardio Plan", systemImage: "figure.run")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingNewPlan) {
                NavigationStack {
                    NewPlanSheet(planType: newPlanType)
                }
            }
        }
    }

    // MARK: - Today's Workout

    @ViewBuilder
    private var todaySection: some View {
        let todayDays = planManager.todaysWorkout()

        if !todayDays.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("TODAY")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(todayDays) { day in
                    todayCard(day: day)
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "figure.cooldown")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Rest Day")
                    .font(.headline)
                Text("No workouts scheduled today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private func todayCard(day: WorkoutPlanDay) -> some View {
        let isStrength = day.plan?.planType == .strength

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isStrength ? "dumbbell.fill" : "figure.run")
                    .foregroundStyle(isStrength ? .orange : .green)
                Text(day.dayLabel)
                    .font(.headline)
                Spacer()
                if let plan = day.plan {
                    Text(plan.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isStrength {
                let exercises = day.sortedStrengthExercises
                if !exercises.isEmpty {
                    Text(exercises.map(\.compactLabel).joined(separator: "  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(day.totalSets) sets · ~\(day.totalSets * 3) min")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                let exercises = day.sortedCardioExercises
                ForEach(exercises) { cardioEx in
                    HStack(spacing: 4) {
                        Text(cardioEx.exercise?.name ?? "–")
                            .font(.caption)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(cardioEx.sessionType.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(cardioEx.targetLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Start button (placeholder for W2/W3)
            Button {
                // Will be wired in W2/W3
            } label: {
                Text(isStrength ? "Start Strength" : "Start Cardio")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isStrength ? Color.orange : Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - My Plans

    @ViewBuilder
    private var myPlansSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MY PLANS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if visiblePlans.isEmpty {
                Text("No plans yet — tap + to create one")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(visiblePlans) { plan in
                    NavigationLink {
                        if plan.planType == .strength {
                            StrengthPlanEditorView(plan: plan)
                        } else {
                            CardioPlanEditorView(plan: plan)
                        }
                    } label: {
                        planRow(plan: plan)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func planRow(plan: WorkoutPlan) -> some View {
        HStack(spacing: 12) {
            Image(systemName: plan.planType == .strength ? "dumbbell.fill" : "figure.run")
                .foregroundStyle(plan.planType == .strength ? .orange : .green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name)
                    .font(.body)
                HStack(spacing: 4) {
                    Image(systemName: plan.status.icon)
                        .font(.caption2)
                    Text(plan.status.displayName)
                        .font(.caption)
                }
                .foregroundStyle(plan.isActive ? .green : .secondary)
            }

            Spacer()

            Text("\(plan.trainingDays.count) days")
                .font(.caption)
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Quick Links

    private var quickLinksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                ExerciseLibraryView()
            } label: {
                quickLink(icon: "books.vertical", title: "Exercise Library", color: .blue)
            }

            NavigationLink {
                MuscleGlossaryView()
            } label: {
                quickLink(icon: "figure.strengthtraining.traditional", title: "Muscle Glossary", color: .purple)
            }

            // Analytics placeholder (W4)
            quickLink(icon: "chart.xyaxis.line", title: "Analytics", color: .teal)
                .opacity(0.5)
        }
    }

    private func quickLink(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(title)
                .font(.body)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Recent Sessions

    @ViewBuilder
    private var recentSessionsSection: some View {
        let sessions: [(String, String, String)] = buildRecentSessions()

        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("RECENT")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(sessions, id: \.0) { (label, subtitle, duration) in
                    HStack {
                        Text(label)
                            .font(.body)
                        Spacer()
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(duration)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func buildRecentSessions() -> [(String, String, String)] {
        var result: [(String, String, String)] = []

        for s in recentStrength.prefix(3) where s.status == .completed {
            let ago = s.date.formatted(.relative(presentation: .named))
            result.append((s.dayLabel, ago, s.durationFormatted))
        }
        for s in recentCardio.prefix(3) where s.status == .completed {
            let ago = s.date.formatted(.relative(presentation: .named))
            result.append((s.dayLabel, ago, s.durationFormatted))
        }

        return result.sorted { $0.1 < $1.1 }.prefix(5).map { $0 }
    }
}

// MARK: - New Plan Sheet

struct NewPlanSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let planType: ExerciseType

    @State private var planName = ""

    var body: some View {
        Form {
            Section("Plan Name") {
                TextField(planType == .strength ? "e.g. PPL Split" : "e.g. Cardio 3x", text: $planName)
            }

            Section {
                Text("Type: \(planType.displayName)")
                    .foregroundStyle(.secondary)
                Text("Creates a 7-day weekly plan (Mon–Sun). You can configure exercises after creation.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .navigationTitle("New Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    let manager = WorkoutPlanManager(modelContext: modelContext)
                    _ = manager.createPlan(name: planName, planType: planType)
                    dismiss()
                }
                .disabled(planName.isEmpty)
            }
        }
    }
}
