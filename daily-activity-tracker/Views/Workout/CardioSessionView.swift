import SwiftUI
import SwiftData
import Combine

/// Full-screen cardio session view with timer, adaptive metric tiles, progress, and phase UI.
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
            bottomBar
        }
        .background(Color(.systemGroupedBackground))
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
        .fullScreenCover(isPresented: $showSummary, onDismiss: {
            dismiss()
        }) {
            NavigationStack {
                CardioSummaryView(session: session, sessionManager: sessionManager, cardioPlanExercise: cardioPlanExercise)
            }
        }
    }

    // MARK: - Header

    private var sessionHeader: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.dayLabel)
                        .font(.title2.weight(.bold))
                    HStack(spacing: 6) {
                        Text(exerciseName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(session.sessionType.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isPaused {
                            StatusBadge(text: "Paused", style: .warning)
                        }
                    }
                }

                Spacer()

                Text(elapsedDisplay)
                    .font(.system(.title, design: .monospaced).weight(.bold))
                    .foregroundStyle(isPaused ? WDS.cardioAccent : .primary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Metric Tiles

    private var metricTiles: some View {
        let tiles = buildMetricTiles()

        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ], spacing: 10) {
            ForEach(tiles, id: \.label) { tile in
                MetricChip(icon: tile.icon, value: tile.value, label: tile.label, color: tile.color)
            }
        }
    }

    private struct MetricTileData {
        let icon: String
        let value: String
        let label: String
        let color: Color
    }

    private func buildMetricTiles() -> [MetricTileData] {
        var tiles: [MetricTileData] = []

        tiles.append(MetricTileData(
            icon: "clock", value: elapsedDisplay, label: "Duration", color: WDS.infoAccent
        ))

        let hr = sessionManager.currentHeartRate
        tiles.append(MetricTileData(
            icon: "heart.fill",
            value: hr > 0 ? "\(Int(hr))" : "–",
            label: "bpm",
            color: .red
        ))

        let distKm = sessionManager.distanceKm
        tiles.append(MetricTileData(
            icon: "figure.run",
            value: distKm > 0.01 ? String(format: "%.2f", distKm) : "–",
            label: "km",
            color: WDS.cardioAccent
        ))

        if distKm > 0.1 {
            let paceSecsPerKm = session.activeDuration / distKm
            let pMin = Int(paceSecsPerKm) / 60
            let pSec = Int(paceSecsPerKm) % 60
            tiles.append(MetricTileData(
                icon: "speedometer",
                value: "\(pMin):\(String(format: "%02d", pSec))",
                label: "/km",
                color: .purple
            ))
        }

        let cal = sessionManager.estimatedCalories
        if cal > 0 {
            tiles.append(MetricTileData(
                icon: "flame.fill",
                value: "\(Int(cal))",
                label: "kcal",
                color: WDS.strengthAccent
            ))
        }

        return tiles
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressSection: some View {
        if let planEx = cardioPlanExercise {
            if let targetDist = planEx.targetDistance, targetDist > 0 {
                let actualKm = sessionManager.distanceKm
                premiumProgressBar(
                    current: actualKm,
                    target: targetDist,
                    label: String(format: "%.2f / %.1f km", actualKm, targetDist)
                )
            } else if let targetMin = planEx.targetDurationMin, targetMin > 0 {
                let actualMin = session.activeDuration / 60.0
                premiumProgressBar(
                    current: actualMin,
                    target: Double(targetMin),
                    label: String(format: "%.0f / %d min", actualMin, targetMin)
                )
            }
        }
    }

    private func premiumProgressBar(current: Double, target: Double, label: String) -> some View {
        let fraction = min(current / target, 1.0)
        let complete = current >= target

        return VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(complete
                              ? LinearGradient(colors: [.green, Color(hex: 0x059669)], startPoint: .leading, endPoint: .trailing)
                              : WDS.cardioGradient)
                        .frame(width: geo.size.width * fraction)
                }
                .frame(height: 8)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 14)

            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .premiumCard(padding: 12)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
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

            GradientButton(
                title: "Finish",
                icon: "checkmark.circle.fill",
                gradient: WDS.cardioGradient,
                size: .compact
            ) {
                WDS.hapticSuccess()
                sessionManager.finishSession(session, cardioPlanExercise: cardioPlanExercise)
                showSummary = true
            }

            Button { showAbandonAlert = true } label: {
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
}

// MARK: - Cardio Summary View

struct CardioSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    let session: CardioSession
    let sessionManager: CardioSessionManager
    let cardioPlanExercise: CardioPlanExercise?

    @State private var animateCheck = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                completionBadge
                statsGrid
                doneButton
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Session Complete")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.2)) {
                animateCheck = true
            }
        }
    }

    private var completionBadge: some View {
        let ratio = sessionManager.completionRatio(for: session, target: cardioPlanExercise)
        let isComplete = ratio >= 0.8

        return VStack(spacing: 10) {
            Image(systemName: isComplete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(isComplete ? .green : .orange)
                .scaleEffect(animateCheck ? 1.0 : 0.3)
                .opacity(animateCheck ? 1.0 : 0)

            Text(isComplete ? "Cardio Complete!" : "Partial Session")
                .font(.title3.weight(.bold))

            Text(String(format: "%.0f%% of target", min(ratio, 1.0) * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private var statsGrid: some View {
        let log = session.logs.first

        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                MetricChip(icon: "timer", value: session.durationFormatted, label: "Duration", color: WDS.infoAccent)
                if let dist = log?.distance, dist > 0 {
                    MetricChip(icon: "figure.run", value: String(format: "%.2f", dist), label: "km", color: WDS.cardioAccent)
                }
                if let hr = log?.avgHeartRate, hr > 0 {
                    MetricChip(icon: "heart.fill", value: "\(hr)", label: "bpm", color: .red)
                }
            }
            HStack(spacing: 10) {
                if let pace = log?.formattedPace() {
                    MetricChip(icon: "speedometer", value: pace, label: "/km", color: .purple)
                }
                if let cal = log?.calories, cal > 0 {
                    MetricChip(icon: "flame.fill", value: "\(Int(cal))", label: "kcal", color: WDS.strengthAccent)
                }
            }
        }
    }

    private var doneButton: some View {
        GradientButton(title: "Done", icon: "checkmark", gradient: WDS.cardioGradient) {
            dismiss()
        }
        .padding(.top, 8)
    }
}
