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
            Divider()
            exerciseList
            Divider()
            bottomBar
        }
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
        .fullScreenCover(isPresented: $showSummary) {
            NavigationStack {
                SessionSummaryView(session: session)
            }
        }
    }

    // MARK: - Header (Timer + Status)

    private var sessionHeader: some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.dayLabel)
                        .font(.title2.weight(.bold))
                    Text(session.planName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Timer
                VStack(alignment: .trailing, spacing: 2) {
                    Text(elapsedDisplay)
                        .font(.system(.title, design: .monospaced).weight(.semibold))
                        .foregroundStyle(isPaused ? .orange : .primary)
                    if isPaused {
                        Text("PAUSED")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                    }
                }
            }

            // Progress bar: completed sets vs planned
            if let planDay = session.planDay, planDay.totalSets > 0 {
                let completed = session.completedSets.count
                let planned = planDay.totalSets
                VStack(spacing: 2) {
                    ProgressView(value: Double(min(completed, planned)), total: Double(planned))
                        .tint(completed >= planned ? .green : .orange)
                    Text("\(completed) / \(planned) sets")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - Exercise List

    private var exerciseList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
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

        VStack(alignment: .leading, spacing: 8) {
            // Exercise header
            HStack {
                Text(exercise.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(workingSets.count)/\(targetSets) sets")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(workingSets.count >= targetSets ? .green : .secondary)
                Text("RIR \(rir)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }

            // Logged sets
            if !exerciseSets.isEmpty {
                VStack(spacing: 4) {
                    ForEach(exerciseSets) { setLog in
                        setRow(setLog: setLog)
                    }
                }
            }

            // Input row for new set
            newSetInput(exercise: exercise)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func setRow(setLog: WorkoutSetLog) -> some View {
        HStack(spacing: 8) {
            if setLog.isWarmup {
                Text("W")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
                    .frame(width: 20)
            } else {
                Text("\(setLog.setNumber)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .frame(width: 20)
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
                Text("e1RM: \(String(format: "%.0f", e1rm))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            // Delete button
            Button {
                sessionManager.deleteSet(setLog)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(setLog.isWarmup ? Color.orange.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - New Set Input

    @ViewBuilder
    private func newSetInput(exercise: Exercise) -> some View {
        let exID = exercise.id
        let currentReps = inputState[exID]?.reps ?? 0
        let currentWeight = inputState[exID]?.weight ?? 0

        HStack(spacing: 8) {
            // Reps stepper
            VStack(spacing: 0) {
                Text("Reps")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 4) {
                    Button {
                        adjustInput(exerciseID: exID, repsDelta: -1)
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)

                    Text("\(currentReps)")
                        .font(.body.monospacedDigit().weight(.medium))
                        .frame(width: 30)

                    Button {
                        adjustInput(exerciseID: exID, repsDelta: 1)
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Weight stepper
            VStack(spacing: 0) {
                Text("Weight")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 4) {
                    Button {
                        adjustInput(exerciseID: exID, weightDelta: -2.5)
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)

                    Text(String(format: "%.1f", currentWeight))
                        .font(.body.monospacedDigit().weight(.medium))
                        .frame(width: 50)

                    Button {
                        adjustInput(exerciseID: exID, weightDelta: 2.5)
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Log set button
            Button {
                logCurrentSet(exerciseID: exID, exercise: exercise, isWarmup: false)
            } label: {
                Text("Log")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(currentReps <= 0)

            // Warmup button
            Button {
                logCurrentSet(exerciseID: exID, exercise: exercise, isWarmup: true)
            } label: {
                Text("W")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.2))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(currentReps <= 0)
        }
        .padding(.top, 4)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 16) {
            // Pause / Resume
            Button {
                if isPaused {
                    sessionManager.resumeSession(session)
                } else {
                    sessionManager.pauseSession(session)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    Text(isPaused ? "Resume" : "Pause")
                }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Finish
            Button {
                sessionManager.finishSession(session)
                showSummary = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Finish")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Abandon
            Button {
                showAbandonAlert = true
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.title3)
                    .foregroundStyle(.red.opacity(0.7))
            }
        }
        .padding()
        .background(Color(.systemBackground))
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
