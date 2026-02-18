import SwiftUI
import SwiftData
import Combine

/// Full-screen cardio session view with timer, adaptive metric tiles, progress bar, and phase UI.
struct CardioSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: CardioSession
    @ObservedObject var sessionManager: CardioSessionManager
    let cardioPlanExercise: CardioPlanExercise?

    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var elapsedDisplay = "0:00"
    @State private var showAbandonAlert = false
    @State private var showSummary = false

    private var isPaused: Bool { session.status == .paused }

    private var exerciseName: String {
        cardioPlanExercise?.exercise?.name ?? "Cardio"
    }

    var body: some View {
        VStack(spacing: 0) {
            sessionHeader
            Divider()
            ScrollView {
                VStack(spacing: 16) {
                    metricTiles
                    progressSection
                    if let planEx = cardioPlanExercise {
                        CardioSessionPhaseView(
                            sessionType: planEx.sessionType,
                            planExercise: planEx,
                            elapsedSeconds: session.activeDuration
                        )
                    }
                }
                .padding()
            }
            Divider()
            bottomBar
        }
        .navigationBarBackButtonHidden(true)
        .onReceive(timer) { _ in
            updateTimer()
        }
        .onAppear { updateTimer() }
        .alert("Abandon Session?", isPresented: $showAbandonAlert) {
            Button("Continue", role: .cancel) { }
            Button("Abandon", role: .destructive) {
                sessionManager.abandonSession(session)
                dismiss()
            }
        } message: {
            Text("Session data will be discarded.")
        }
        .fullScreenCover(isPresented: $showSummary) {
            NavigationStack {
                CardioSummaryView(session: session, sessionManager: sessionManager, cardioPlanExercise: cardioPlanExercise)
            }
        }
    }

    // MARK: - Header

    private var sessionHeader: some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.dayLabel)
                        .font(.title2.weight(.bold))
                    HStack(spacing: 4) {
                        Text(exerciseName)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(session.sessionType.displayName)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
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
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - Adaptive Metric Tiles

    private var metricTiles: some View {
        let tiles = buildMetricTiles()

        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ], spacing: 10) {
            ForEach(tiles, id: \.label) { tile in
                metricTile(icon: tile.icon, value: tile.value, label: tile.label, color: tile.color)
            }
        }
    }

    private struct MetricTile {
        let icon: String
        let value: String
        let label: String
        let color: Color
    }

    private func buildMetricTiles() -> [MetricTile] {
        var tiles: [MetricTile] = []

        // Duration — always shown
        tiles.append(MetricTile(
            icon: "clock", value: elapsedDisplay, label: "Duration", color: .blue
        ))

        // Heart Rate
        let hr = sessionManager.currentHeartRate
        tiles.append(MetricTile(
            icon: "heart.fill",
            value: hr > 0 ? "\(Int(hr))" : "–",
            label: "bpm",
            color: .red
        ))

        // Distance
        let distKm = sessionManager.distanceKm
        tiles.append(MetricTile(
            icon: "figure.run",
            value: distKm > 0.01 ? String(format: "%.2f", distKm) : "–",
            label: "km",
            color: .green
        ))

        // Pace (sec/km → min:sec)
        if distKm > 0.1 {
            let paceSecsPerKm = session.activeDuration / distKm
            let pMin = Int(paceSecsPerKm) / 60
            let pSec = Int(paceSecsPerKm) % 60
            tiles.append(MetricTile(
                icon: "speedometer",
                value: "\(pMin):\(String(format: "%02d", pSec))",
                label: "/km",
                color: .purple
            ))
        }

        // Calories
        let cal = sessionManager.estimatedCalories
        if cal > 0 {
            tiles.append(MetricTile(
                icon: "flame.fill",
                value: "\(Int(cal))",
                label: "kcal",
                color: .orange
            ))
        }

        return tiles
    }

    private func metricTile(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressSection: some View {
        if let planEx = cardioPlanExercise {
            if let targetDist = planEx.targetDistance, targetDist > 0 {
                let actualKm = sessionManager.distanceKm
                progressBar(
                    current: actualKm,
                    target: targetDist,
                    label: String(format: "%.2f / %.1f km", actualKm, targetDist)
                )
            } else if let targetMin = planEx.targetDurationMin, targetMin > 0 {
                let actualMin = session.activeDuration / 60.0
                progressBar(
                    current: actualMin,
                    target: Double(targetMin),
                    label: String(format: "%.0f / %d min", actualMin, targetMin)
                )
            }
        }
    }

    private func progressBar(current: Double, target: Double, label: String) -> some View {
        VStack(spacing: 4) {
            ProgressView(value: min(current, target), total: target)
                .tint(current >= target ? .green : .orange)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 16) {
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

            Button {
                sessionManager.finishSession(session, cardioPlanExercise: cardioPlanExercise)
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

            Button { showAbandonAlert = true } label: {
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
}

// MARK: - Cardio Summary View

struct CardioSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    let session: CardioSession
    let sessionManager: CardioSessionManager
    let cardioPlanExercise: CardioPlanExercise?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                completionBadge
                statsGrid
                doneButton
            }
            .padding()
        }
        .navigationTitle("Session Complete")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var completionBadge: some View {
        let ratio = sessionManager.completionRatio(for: session, target: cardioPlanExercise)
        let isComplete = ratio >= 0.8

        return VStack(spacing: 8) {
            Image(systemName: isComplete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(isComplete ? .green : .orange)
            Text(isComplete ? "Cardio Complete!" : "Partial Session")
                .font(.title3.weight(.bold))
            Text(String(format: "%.0f%% of target", min(ratio, 1.0) * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var statsGrid: some View {
        let log = session.logs.first

        return VStack(spacing: 10) {
            HStack(spacing: 16) {
                statCard(title: "Duration", value: session.durationFormatted, icon: "timer")
                if let dist = log?.distance, dist > 0 {
                    statCard(title: "Distance", value: String(format: "%.2f km", dist), icon: "figure.run")
                }
                if let hr = log?.avgHeartRate, hr > 0 {
                    statCard(title: "Avg HR", value: "\(hr) bpm", icon: "heart.fill")
                }
            }
            HStack(spacing: 16) {
                if let pace = log?.formattedPace() {
                    statCard(title: "Pace", value: pace, icon: "speedometer")
                }
                if let cal = log?.calories, cal > 0 {
                    statCard(title: "Calories", value: "\(Int(cal)) kcal", icon: "flame.fill")
                }
            }
        }
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.green)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top, 8)
    }
}
