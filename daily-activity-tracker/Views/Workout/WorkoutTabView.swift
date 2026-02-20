import SwiftUI
import SwiftData

/// Main Workout Tab — today's workout, plans, quick links, recent sessions.
struct WorkoutTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutPlan.createdAt, order: .reverse) private var allPlans: [WorkoutPlan]
    @Query(sort: \StrengthSession.startedAt, order: .reverse) private var recentStrength: [StrengthSession]
    @Query(sort: \CardioSession.startedAt, order: .reverse) private var recentCardio: [CardioSession]

    @State private var showingNewPlan = false
    @State private var newPlanType: ExerciseType = .strength
    @State private var activeStrengthSession: StrengthSession?
    @State private var showStrengthSession = false
    @State private var activeCardioSession: CardioSession?
    @State private var activeCardioPlanExercise: CardioPlanExercise?
    @State private var showCardioSession = false
    @State private var selectedSummarySession: StrengthSession?
    @State private var selectedCardioSummarySession: CardioSession?
    @State private var recoverySession: StrengthSession?
    @State private var showRecoveryAlert = false
    @State private var showCardioExercisePicker = false
    @State private var pendingCardioDay: WorkoutPlanDay?

    @StateObject private var cardioManager = CardioSessionManager()

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
                VStack(spacing: 24) {
                    activeSessionBanner
                    todaySection
                    myPlansSection
                    inactivePlansSection
                    quickLinksSection
                    recentSessionsSection
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Workout")
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
                            Label("Strength Plan", systemImage: "dumbbell.fill")
                        }
                        Button {
                            newPlanType = .cardio
                            showingNewPlan = true
                        } label: {
                            Label("Cardio Plan", systemImage: "figure.run")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                    }
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
            .sheet(isPresented: $showingNewPlan) {
                NavigationStack { NewPlanSheet(planType: newPlanType) }
            }
            .sheet(item: $selectedSummarySession) { session in
                NavigationStack { SessionSummaryView(session: session) }
            }
            .sheet(item: $selectedCardioSummarySession) { session in
                NavigationStack {
                    CardioSummaryView(
                        session: session,
                        sessionManager: cardioManager,
                        cardioPlanExercise: session.planDay?.sortedCardioExercises.first
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
                    }
                }
                Button("Cancel", role: .cancel) { }
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
                HStack(spacing: 12) {
                    // Pulsing indicator + icon
                    ZStack {
                        Circle()
                            .fill(WDS.strengthGradient)
                            .frame(width: 44, height: 44)
                        Image(systemName: active.status == .paused ? "pause.fill" : "bolt.fill")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            PulsingDot(color: active.status == .paused ? .orange : .green)
                            Text(active.status == .paused ? "PAUSED" : "LIVE")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(active.status == .paused ? .orange : .green)
                        }
                        Text(active.dayLabel)
                            .font(.headline)
                    }

                    Spacer()

                    // Timer
                    Text(active.durationFormatted)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(WDS.strengthAccent)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .premiumCard(accent: active.status == .paused ? .orange : .green)
            }
            .buttonStyle(ScaleButtonStyle())
        }
    }

    // MARK: - Today's Workout

    @ViewBuilder
    private var todaySection: some View {
        let todayDays = planManager.todaysWorkout()

        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Today")

            if todayDays.isEmpty {
                emptyTodayCard
            } else {
                ForEach(todayDays) { day in
                    todayCard(day: day)
                }
            }
        }
    }

    private var emptyTodayCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Rest Day")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("No workouts scheduled")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .premiumCard()
    }

    @ViewBuilder
    private func todayCard(day: WorkoutPlanDay) -> some View {
        let isStrength = day.plan?.planType == .strength
        let accent: Color = isStrength ? WDS.strengthAccent : WDS.cardioAccent
        let gradient = isStrength ? WDS.strengthGradient : WDS.cardioGradient

        VStack(alignment: .leading, spacing: 14) {
            // Header row
            HStack(spacing: 10) {
                IconBadge(icon: isStrength ? "dumbbell.fill" : "figure.run", color: accent, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(day.dayLabel)
                        .font(.headline)
                    if let plan = day.plan {
                        Text(plan.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isStrength && day.totalSets > 0 {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(day.totalSets)")
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(accent)
                        Text("sets")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Exercise list
            if isStrength {
                let exercises = day.sortedStrengthExercises
                if !exercises.isEmpty {
                    HStack(spacing: 0) {
                        Text(exercises.map(\.compactLabel).joined(separator: "  ·  "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } else {
                let exercises = day.sortedCardioExercises
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(exercises) { cardioEx in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(accent.opacity(0.5))
                                .frame(width: 5, height: 5)
                            Text(cardioEx.exercise?.name ?? "–")
                                .font(.subheadline)
                            Text(cardioEx.sessionType.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Action button
            switch planManager.todaySessionStatus(for: day) {
            case .fullyCompleted:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Completed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: WDS.buttonRadius, style: .continuous))

            case .incomplete(let done, let total):
                GradientButton(
                    title: "Continue",
                    icon: "arrow.counterclockwise",
                    gradient: gradient,
                    size: .compact
                ) {
                    if isStrength {
                        continueStrengthSession(day: day)
                    } else {
                        startCardioSession(day: day)
                    }
                }
                .overlay(alignment: .trailing) {
                    Text("\(done)/\(total)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.trailing, 12)
                }

            case .notStarted:
                GradientButton(
                    title: isStrength ? "Start Strength" : "Start Cardio",
                    icon: "play.fill",
                    gradient: gradient,
                    size: .compact
                ) {
                    if isStrength {
                        startStrengthSession(day: day)
                    } else {
                        startCardioSession(day: day)
                    }
                }
            }
        }
        .premiumCard(accent: accent)
        .id(refreshID)
    }

    // MARK: - My Plans

    @ViewBuilder
    private var myPlansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "My Plans")

            if visiblePlans.isEmpty {
                HStack {
                    Image(systemName: "doc.badge.plus")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("No plans yet — tap + to create one")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .premiumCard()
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
                    .buttonStyle(ScaleButtonStyle())
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
                    inactivePlanRow(plan: plan)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "archivebox.fill")
                        .foregroundStyle(.secondary)
                    Text("Inactive Plans")
                        .font(.subheadline.weight(.semibold))
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

    private func inactivePlanRow(plan: WorkoutPlan) -> some View {
        HStack(spacing: 12) {
            IconBadge(
                icon: plan.planType == .strength ? "dumbbell.fill" : "figure.run",
                color: .secondary,
                size: 32
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(plan.name)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    if plan.isDraft {
                        StatusBadge(text: "Draft", style: .draft)
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
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.12))
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

    @ViewBuilder
    private func planRow(plan: WorkoutPlan) -> some View {
        let isStrength = plan.planType == .strength
        let accent: Color = isStrength ? WDS.strengthAccent : WDS.cardioAccent

        HStack(spacing: 12) {
            // Accent stripe
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 4, height: 44)

            IconBadge(
                icon: isStrength ? "dumbbell.fill" : "figure.run",
                color: accent,
                size: 36
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(plan.name)
                        .font(.body.weight(.medium))
                    if plan.isDraft {
                        StatusBadge(text: "Draft", style: .draft)
                    }
                }
                HStack(spacing: 6) {
                    Circle()
                        .fill(plan.isActive ? .green : .secondary)
                        .frame(width: 6, height: 6)
                    Text(plan.status.displayName)
                        .font(.caption)
                        .foregroundStyle(plan.isActive ? .green : .secondary)
                }
            }

            Spacer()

            Text("\(plan.trainingDays.count)d")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .premiumCard(accent: accent, padding: 12)
    }

    // MARK: - Quick Links

    private var quickLinksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Explore")

            HStack(spacing: 12) {
                NavigationLink {
                    ExerciseLibraryView()
                } label: {
                    quickLinkPill(icon: "books.vertical.fill", title: "Exercises", color: WDS.infoAccent)
                }
                .buttonStyle(ScaleButtonStyle())

                NavigationLink {
                    MuscleGlossaryView()
                } label: {
                    quickLinkPill(icon: "figure.strengthtraining.traditional", title: "Muscles", color: .purple)
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
    }

    private func quickLinkPill(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .premiumCard(accent: color, padding: 14)
    }

    // MARK: - Recent Sessions

    @ViewBuilder
    private var recentSessionsSection: some View {
        let completedStrength = recentStrength.filter { $0.status == .completed }.prefix(5)
        let completedCardio = recentCardio.filter { $0.status == .completed }.prefix(3)

        if !completedStrength.isEmpty || !completedCardio.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Recent")

                ForEach(Array(completedStrength)) { session in
                    Button {
                        selectedSummarySession = session
                    } label: {
                        sessionRow(
                            icon: "dumbbell.fill",
                            color: WDS.strengthAccent,
                            label: session.dayLabel,
                            date: session.date,
                            duration: session.durationFormatted
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .contextMenu {
                        Button(role: .destructive) {
                            sessionManager.deleteSession(session)
                            refreshID = UUID()
                        } label: {
                            Label("Delete Session", systemImage: "trash")
                        }
                    }
                }

                ForEach(Array(completedCardio)) { session in
                    Button {
                        selectedCardioSummarySession = session
                    } label: {
                        sessionRow(
                            icon: "figure.run",
                            color: WDS.cardioAccent,
                            label: session.dayLabel,
                            date: session.date,
                            duration: session.durationFormatted
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
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

    private func sessionRow(icon: String, color: Color, label: String, date: Date, duration: String) -> some View {
        HStack(spacing: 12) {
            // Colored left bar
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 3, height: 32)

            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 20)

            Text(label)
                .font(.subheadline.weight(.medium))

            Spacer()

            Text(date.formatted(.relative(presentation: .named)))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(duration)
                .font(.caption.weight(.medium).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemGray6).opacity(0.8))
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

    private func continueStrengthSession(day: WorkoutPlanDay) {
        if let existing = sessionManager.activeSession() {
            activeStrengthSession = existing
            showStrengthSession = true
            return
        }

        if let incomplete = sessionManager.findIncompleteSession(for: day) {
            sessionManager.resumeCompletedSession(incomplete)
            activeStrengthSession = incomplete
            showStrengthSession = true
            return
        }

        startStrengthSession(day: day)
    }

    private func startCardioSession(day: WorkoutPlanDay) {
        let cardioExercises = day.sortedCardioExercises
        guard !cardioExercises.isEmpty else { return }

        if cardioExercises.count == 1 {
            launchCardioSession(day: day, exercise: cardioExercises[0])
        } else {
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
                HStack(spacing: 10) {
                    IconBadge(
                        icon: planType == .strength ? "dumbbell.fill" : "figure.run",
                        color: planType == .strength ? WDS.strengthAccent : WDS.cardioAccent,
                        size: 32
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Type: \(planType.displayName)")
                            .font(.subheadline)
                        Text("Creates a 7-day weekly plan (Mon–Sun)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
