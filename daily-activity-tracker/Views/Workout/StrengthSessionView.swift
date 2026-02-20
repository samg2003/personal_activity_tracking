import SwiftUI
import SwiftData
import Combine

/// Full-screen strength workout session view with timer, exercise cards, and set logging.
struct StrengthSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: StrengthSession

    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var elapsedDisplay = "0:00"
    @State private var showAbandonAlert = false
    @State private var showSummary = false

    // Per-exercise input state: [exerciseID: (reps, weight)]
    @State private var inputState: [UUID: (reps: Int, weight: Double)] = [:]

    private var sessionManager: StrengthSessionManager {
        StrengthSessionManager(modelContext: modelContext)
    }

    private var isPaused: Bool {
        session.status == .paused
    }

    var body: some View {
        VStack(spacing: 0) {
            sessionHeader
            exerciseList
            bottomBar
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarBackButtonHidden(true)
        .onReceive(timer) { _ in
            updateTimer()
        }
        .onAppear {
            initializeInputState()
            updateTimer()
        }
        .alert("Abandon Session?", isPresented: $showAbandonAlert) {
            Button("Continue Workout", role: .cancel) { }
            Button("Abandon", role: .destructive) {
                sessionManager.abandonSession(session)
                dismiss()
            }
        } message: {
            if session.resumedAtSetCount >= 0 {
                Text("Sets added during this continuation will be removed. Your original workout data will be preserved.")
            } else {
                Text("Your logged sets will be saved but the session won't count toward your plan completion.")
            }
        }
        .fullScreenCover(isPresented: $showSummary, onDismiss: {
            dismiss()
        }) {
            NavigationStack {
                SessionSummaryView(session: session)
            }
        }
    }

    // MARK: - Header

    private var sessionHeader: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.dayLabel)
                        .font(.title2.weight(.bold))
                    HStack(spacing: 6) {
                        Text(session.planName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isPaused {
                            StatusBadge(text: "Paused", style: .warning)
                        }
                    }
                }

                Spacer()

                // Timer display
                Text(elapsedDisplay)
                    .font(.system(.title, design: .monospaced).weight(.bold))
                    .foregroundStyle(isPaused ? WDS.strengthAccent : .primary)
            }

            // Progress ring + set count
            if let planDay = session.planDay, planDay.totalSets > 0 {
                let completed = session.completedSets.count
                let planned = planDay.totalSets
                let progress = Double(min(completed, planned)) / Double(planned)

                HStack(spacing: 12) {
                    ProgressRing(
                        progress: progress,
                        lineWidth: 5,
                        gradient: completed >= planned
                            ? LinearGradient(colors: [.green, .green], startPoint: .leading, endPoint: .trailing)
                            : WDS.strengthGradient,
                        size: 36
                    )

                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(completed) / \(planned) sets")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                        Text(completed >= planned ? "All sets done!" : "\(planned - completed) remaining")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Exercise List

    private var exerciseList: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if let planDay = session.planDay {
                    ForEach(planDay.sortedStrengthExercises) { planEx in
                        if let exercise = planEx.exercise {
                            exerciseCard(exercise: exercise, targetSets: planEx.targetSets, rir: planEx.rir)
                        }
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func exerciseCard(exercise: Exercise, targetSets: Int, rir: Int) -> some View {
        let exerciseSets = session.setLogs
            .filter { $0.exercise?.id == exercise.id }
            .sorted { $0.setNumber < $1.setNumber }
        let workingSets = exerciseSets.filter { !$0.isWarmup }

        VStack(alignment: .leading, spacing: 10) {
            // Exercise header
            HStack {
                Text(exercise.displayName)
                    .font(.subheadline.weight(.bold))
                Spacer()

                HStack(spacing: 8) {
                    Text("\(workingSets.count)/\(targetSets)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(workingSets.count >= targetSets ? .green : WDS.strengthAccent)

                    Text("RIR \(rir)")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(WDS.strengthAccent.opacity(0.1))
                        .foregroundStyle(WDS.strengthAccent)
                        .clipShape(Capsule())
                }
            }

            // Logged sets
            if !exerciseSets.isEmpty {
                VStack(spacing: 2) {
                    ForEach(Array(exerciseSets.enumerated()), id: \.element.id) { index, setLog in
                        setRow(setLog: setLog, isEven: index % 2 == 0)
                    }
                }
            }

            // Input row
            newSetInput(exercise: exercise)
        }
        .premiumCard(accent: workingSets.count >= targetSets ? .green : .clear)
    }

    @ViewBuilder
    private func setRow(setLog: WorkoutSetLog, isEven: Bool) -> some View {
        HStack(spacing: 8) {
            if setLog.isWarmup {
                Text("W")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.orange)
                    .frame(width: 22)
            } else {
                Text("\(setLog.setNumber)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(width: 22)
            }

            if let dur = setLog.durationSeconds {
                Text("\(dur)s")
                    .font(.caption.monospacedDigit())
            } else {
                Text("\(setLog.reps) × \(String(format: "%.1f", setLog.weight))kg")
                    .font(.caption.monospacedDigit())
            }

            Spacer()

            if let e1rm = setLog.estimated1RM {
                Text("e1RM \(String(format: "%.0f", e1rm))")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            Button {
                sessionManager.deleteSet(setLog)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isEven ? Color(.systemGray6).opacity(0.5) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    // MARK: - New Set Input

    @ViewBuilder
    private func newSetInput(exercise: Exercise) -> some View {
        let exID = exercise.id
        let currentReps = inputState[exID]?.reps ?? 0
        let currentWeight = inputState[exID]?.weight ?? 0

        HStack(spacing: 6) {
            // Reps
            VStack(spacing: 2) {
                Text("Reps")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 3) {
                    Button { adjustInput(exerciseID: exID, repsDelta: -1) } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 26, height: 26)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Text("\(currentReps)")
                        .font(.body.monospacedDigit().weight(.semibold))
                        .frame(width: 28)

                    Button { adjustInput(exerciseID: exID, repsDelta: 1) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 26, height: 26)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Weight
            VStack(spacing: 2) {
                Text("Weight")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 3) {
                    Button { adjustInput(exerciseID: exID, weightDelta: -2.5) } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 26, height: 26)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Text(String(format: "%.1f", currentWeight))
                        .font(.body.monospacedDigit().weight(.semibold))
                        .frame(width: 46)

                    Button { adjustInput(exerciseID: exID, weightDelta: 2.5) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 26, height: 26)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            VStack(spacing: 4) {
                // Log button
                Button {
                    WDS.hapticMedium()
                    logCurrentSet(exerciseID: exID, exercise: exercise, isWarmup: false)
                } label: {
                    Text("Log")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(WDS.strengthGradient)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(currentReps <= 0)

                // Warmup
                Button {
                    WDS.hapticLight()
                    logCurrentSet(exerciseID: exID, exercise: exercise, isWarmup: true)
                } label: {
                    Text("W")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(WDS.strengthAccent.opacity(0.15))
                        .foregroundStyle(WDS.strengthAccent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(currentReps <= 0)
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            // Pause / Resume
            Button {
                WDS.hapticMedium()
                if isPaused {
                    sessionManager.resumeSession(session)
                } else {
                    sessionManager.pauseSession(session)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    Text(isPaused ? "Resume" : "Pause")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: WDS.buttonRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: WDS.buttonRadius, style: .continuous)
                        .strokeBorder(Color(.systemGray4), lineWidth: 0.5)
                )
            }
            .buttonStyle(ScaleButtonStyle())

            // Finish
            GradientButton(
                title: "Finish",
                icon: "checkmark.circle.fill",
                gradient: LinearGradient(colors: [.green, Color(hex: 0x059669)], startPoint: .leading, endPoint: .trailing),
                size: .compact
            ) {
                WDS.hapticSuccess()
                sessionManager.finishSession(session)
                showSummary = true
            }

            // Abandon
            Button {
                showAbandonAlert = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func updateTimer() {
        guard session.status != .completed && session.status != .abandoned else { return }
        elapsedDisplay = session.durationFormatted
    }

    private func initializeInputState() {
        guard let planDay = session.planDay else { return }
        for planEx in planDay.sortedStrengthExercises {
            guard let exercise = planEx.exercise else { continue }
            let suggestion = sessionManager.autoFillSuggestion(for: exercise)
            inputState[exercise.id] = (
                reps: suggestion?.reps ?? 10,
                weight: suggestion?.weight ?? 0
            )
        }
    }

    private func adjustInput(exerciseID: UUID, repsDelta: Int = 0, weightDelta: Double = 0) {
        var current = inputState[exerciseID] ?? (reps: 10, weight: 0)
        current.reps = max(0, current.reps + repsDelta)
        current.weight = max(0, current.weight + weightDelta)
        inputState[exerciseID] = current
    }

    private func logCurrentSet(exerciseID: UUID, exercise: Exercise, isWarmup: Bool) {
        let current = inputState[exerciseID] ?? (reps: 0, weight: 0)
        guard current.reps > 0 else { return }

        sessionManager.logSet(
            session: session,
            exercise: exercise,
            reps: current.reps,
            weight: current.weight,
            isWarmup: isWarmup
        )
    }
}
