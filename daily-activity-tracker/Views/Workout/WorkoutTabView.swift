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

    // Strength session navigation
    @State private var activeStrengthSession: StrengthSession?
    @State private var showStrengthSession = false
    @State private var showRecoveryAlert = false
    @State private var recoverySession: StrengthSession?
    @State private var selectedSummarySession: StrengthSession?

    // Cardio session navigation
    @State private var activeCardioSession: CardioSession?
    @State private var showCardioSession = false
    @State private var activeCardioPlanExercise: CardioPlanExercise?
    @StateObject private var cardioManager = CardioSessionManager()
    @State private var selectedCardioSummarySession: CardioSession?
    @State private var showCardioExercisePicker = false
    @State private var pendingCardioDay: WorkoutPlanDay?

    private var planManager: WorkoutPlanManager {
        WorkoutPlanManager(modelContext: modelContext)
    }

    private var sessionManager: StrengthSessionManager {
        StrengthSessionManager(modelContext: modelContext)
    }

    private var visiblePlans: [WorkoutPlan] {
        allPlans.filter { $0.status != .inactive }
    }

    private var inactivePlans: [WorkoutPlan] {
        allPlans.filter { $0.status == .inactive }
    }

    @State private var inactivePlansExpanded = false
    @State private var refreshID = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    activeSessionBanner
                    todaySection
                    myPlansSection
                    inactivePlansSection
                    quickLinksSection
                    recentSessionsSection
                }
                .padding()
            }
            .navigationTitle("Workouts")
            .onAppear { refreshID = UUID() }
            .onChange(of: showStrengthSession) { _, showing in
                if !showing { refreshID = UUID() }
            }
            .onChange(of: showCardioSession) { _, showing in
                if !showing { refreshID = UUID() }
            }
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
            .navigationDestination(isPresented: $showStrengthSession) {
                if let session = activeStrengthSession {
                    StrengthSessionView(session: session)
                }
            }
            .navigationDestination(isPresented: $showCardioSession) {
                if let session = activeCardioSession {
                    CardioSessionView(
                        session: session,
                        sessionManager: cardioManager,
                        cardioPlanExercise: activeCardioPlanExercise
                    )
                }
            }
            .sheet(item: $selectedSummarySession) { session in
                NavigationStack {
                    SessionSummaryView(session: session)
                }
            }
            .sheet(item: $selectedCardioSummarySession) { session in
                NavigationStack {
                    CardioSummaryView(
                        session: session,
                        sessionManager: cardioManager,
                        cardioPlanExercise: nil
                    )
                }
            }
            .sheet(isPresented: $showCardioExercisePicker) {
                if let day = pendingCardioDay {
                    cardioExercisePickerSheet(day: day)
                }
            }
            .onAppear {
                cardioManager.updateModelContext(modelContext)
                checkForActiveSession()
            }
            .alert("Resume Workout?", isPresented: $showRecoveryAlert) {
                Button("Resume") {
                    if let session = recoverySession {
                        activeStrengthSession = session
                        showStrengthSession = true
                    }
                }
                Button("Abandon", role: .destructive) {
                    if let session = recoverySession {
                        sessionManager.abandonSession(session)
                        recoverySession = nil
                    }
                }
            } message: {
                if let session = recoverySession {
                    Text("You have an unfinished \"\(session.dayLabel)\" session from \(session.startedAt.formatted(.relative(presentation: .named))). Would you like to continue?")
                }
            }
        }
    }

    // MARK: - Active Session Banner

    @ViewBuilder
    private var activeSessionBanner: some View {
        if let active = sessionManager.activeSession(), active.status != .completed && active.status != .abandoned {
            Button {
                activeStrengthSession = active
                showStrengthSession = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: active.status == .paused ? "pause.circle.fill" : "bolt.fill")
                        .font(.title3)
                        .foregroundStyle(active.status == .paused ? .orange : .green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Session In Progress")
                            .font(.subheadline.weight(.semibold))
                        Text("\(active.dayLabel) · \(active.durationFormatted)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("Resume")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
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

            // Start / Continue / Completed badge
            switch planManager.todaySessionStatus(for: day) {
            case .fullyCompleted:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Completed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            case .incomplete(let done, let total):
                Button {
                    if isStrength {
                        continueStrengthSession(day: day)
                    } else {
                        startCardioSession(day: day)
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Continue Workout")
                        Text("(\(done)/\(total) sets)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

            case .notStarted:
                Button {
                    if isStrength {
                        startStrengthSession(day: day)
                    } else {
                        startCardioSession(day: day)
                    }
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
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .id(refreshID)
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
                    .contextMenu {
                        if plan.isDraft {
                            Button(role: .destructive) {
                                planManager.permanentlyDeletePlan(plan)
                            } label: {
                                Label("Delete Draft", systemImage: "trash")
                            }
                        }
                        Button(role: .destructive) {
                            planManager.deactivatePlan(plan)
                        } label: {
                            Label("Deactivate", systemImage: "archivebox")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Inactive Plans

    @State private var planToDelete: WorkoutPlan?
    @State private var showDeleteConfirmation = false

    @ViewBuilder
    private var inactivePlansSection: some View {
        if !inactivePlans.isEmpty {
            DisclosureGroup(isExpanded: $inactivePlansExpanded) {
                ForEach(inactivePlans) { plan in
                    HStack(spacing: 12) {
                        Image(systemName: plan.planType == .strength ? "dumbbell.fill" : "figure.run")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(plan.name)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                if plan.isDraft {
                                    Text("DRAFT")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.orange.opacity(0.2))
                                        .foregroundStyle(.orange)
                                        .clipShape(Capsule())
                                }
                            }
                            Text("\(plan.trainingDays.count) days")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        Button {
                            planManager.activatePlan(plan)
                        } label: {
                            Text("Reactivate")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.15))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button(role: .destructive) {
                            if planManager.hasLoggedSessions(for: plan) {
                                planToDelete = plan
                                showDeleteConfirmation = true
                            } else {
                                planManager.permanentlyDeletePlan(plan)
                            }
                        } label: {
                            Label("Delete Plan", systemImage: "trash")
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "archivebox")
                        .foregroundStyle(.secondary)
                    Text("INACTIVE PLANS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("(\(inactivePlans.count))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .tint(.secondary)
            .alert("Delete Plan?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let plan = planToDelete {
                        planManager.permanentlyDeletePlan(plan)
                        planToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { planToDelete = nil }
            } message: {
                Text("This plan has logged sessions. The plan configuration will be removed, but your session history (sets, times) will be preserved.")
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

            // Analytics moved to Analytics tab (W4)
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
        let completedStrength = recentStrength.filter { $0.status == .completed }.prefix(5)

        if !completedStrength.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("RECENT")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(Array(completedStrength)) { session in
                    Button {
                        selectedSummarySession = session
                    } label: {
                        HStack {
                            Image(systemName: "dumbbell.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .frame(width: 20)
                            Text(session.dayLabel)
                                .font(.body)
                            Spacer()
                            Text(session.date.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(session.durationFormatted)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            sessionManager.deleteSession(session)
                            refreshID = UUID()
                        } label: {
                            Label("Delete Session", systemImage: "trash")
                        }
                    }
                }

                ForEach(Array(recentCardio.filter { $0.status == .completed }.prefix(3))) { session in
                    Button {
                        selectedCardioSummarySession = session
                    } label: {
                        HStack {
                            Image(systemName: "figure.run")
                                .font(.caption)
                                .foregroundStyle(.green)
                                .frame(width: 20)
                            Text(session.dayLabel)
                                .font(.body)
                            Spacer()
                            Text(session.date.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(session.durationFormatted)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            modelContext.delete(session)
                            try? modelContext.save()
                            refreshID = UUID()
                        } label: {
                            Label("Delete Session", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func startStrengthSession(day: WorkoutPlanDay) {
        if let existing = sessionManager.activeSession() {
            activeStrengthSession = existing
            showStrengthSession = true
            return
        }

        let session = sessionManager.startSession(for: day)
        activeStrengthSession = session
        showStrengthSession = true
    }

    /// Resumes an incomplete session for the day, preserving all previously logged sets.
    private func continueStrengthSession(day: WorkoutPlanDay) {
        // First check for an already-active session
        if let existing = sessionManager.activeSession() {
            activeStrengthSession = existing
            showStrengthSession = true
            return
        }

        // Find and re-open today's incomplete completed session
        if let incomplete = sessionManager.findIncompleteSession(for: day) {
            sessionManager.resumeCompletedSession(incomplete)
            activeStrengthSession = incomplete
            showStrengthSession = true
            return
        }

        // Fallback: start fresh
        startStrengthSession(day: day)
    }

    private func startCardioSession(day: WorkoutPlanDay) {
        let cardioExercises = day.sortedCardioExercises
        guard !cardioExercises.isEmpty else { return }

        if cardioExercises.count == 1 {
            // Single exercise — start immediately
            launchCardioSession(day: day, exercise: cardioExercises[0])
        } else {
            // Multiple exercises — show picker
            pendingCardioDay = day
            showCardioExercisePicker = true
        }
    }

    private func launchCardioSession(day: WorkoutPlanDay, exercise: CardioPlanExercise) {
        cardioManager.updateModelContext(modelContext)
        let session = cardioManager.startSession(for: day, cardioPlanExercise: exercise)
        activeCardioSession = session
        activeCardioPlanExercise = exercise
        showCardioSession = true
    }

    @ViewBuilder
    private func cardioExercisePickerSheet(day: WorkoutPlanDay) -> some View {
        NavigationStack {
            List(day.sortedCardioExercises) { cardioEx in
                Button {
                    showCardioExercisePicker = false
                    launchCardioSession(day: day, exercise: cardioEx)
                } label: {
                    HStack {
                        Text(cardioEx.exercise?.name ?? "Cardio")
                        Spacer()
                        Text(cardioEx.sessionType.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Choose Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCardioExercisePicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func checkForActiveSession() {
        if let active = sessionManager.activeSession() {
            if !Calendar.current.isDateInToday(active.startedAt) {
                recoverySession = active
                showRecoveryAlert = true
            }
        }
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
