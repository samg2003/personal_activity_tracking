import SwiftUI

/// Adapts based on cardio session type to show phase-specific guidance.
struct CardioSessionPhaseView: View {
    let sessionType: CardioSessionType
    let planExercise: CardioPlanExercise
    let elapsedSeconds: TimeInterval

    @ViewBuilder
    var body: some View {
        switch sessionType {
        case .hiit:
            if let params = planExercise.hiitParams {
                hiitView(params: params)
            }
        case .tempo:
            if let params = planExercise.tempoParams {
                tempoView(params: params)
            }
        case .intervals:
            if let params = planExercise.intervalParams {
                intervalView(params: params)
            }
        case .steadyState:
            if let params = planExercise.steadyStateParams {
                steadyStateView(params: params)
            }
        case .free:
            EmptyView()
        }
    }

    // MARK: - HIIT

    @ViewBuilder
    private func hiitView(params: HIITParams) -> some View {
        let roundDuration = params.workSeconds + params.restSeconds
        let totalElapsed = Int(elapsedSeconds)
        let currentRoundIndex = min(totalElapsed / roundDuration, params.rounds - 1)
        let timeInRound = totalElapsed % roundDuration
        let isWork = timeInRound < params.workSeconds
        let phaseTimeRemaining = isWork
            ? params.workSeconds - timeInRound
            : roundDuration - timeInRound

        VStack(spacing: 12) {
            Text("HIIT")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            // Current phase
            VStack(spacing: 4) {
                Text(isWork ? "WORK" : "REST")
                    .font(.title2.weight(.black))
                    .foregroundStyle(isWork ? .red : .green)

                Text(formatSeconds(phaseTimeRemaining))
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                    .foregroundStyle(isWork ? .red : .green)
            }

            // Round counter
            Text("Round \(currentRoundIndex + 1) / \(params.rounds)")
                .font(.subheadline.weight(.medium))

            // Round dots
            HStack(spacing: 6) {
                ForEach(0..<params.rounds, id: \.self) { i in
                    Circle()
                        .fill(i < currentRoundIndex ? Color.green :
                              i == currentRoundIndex ? (isWork ? Color.red : Color.green) :
                              Color(.systemGray4))
                        .frame(width: 10, height: 10)
                }
            }
        }
        .phaseCard()
    }

    // MARK: - Tempo

    // Helper to compute tempo phase state outside ViewBuilder
    private struct TempoPhaseState {
        let name: String
        let color: Color
        let remaining: Int
        let progress: Double
        let elapsed: Int
        let warmupSec: Int
        let tempoSec: Int
        let cooldownSec: Int

        init(elapsed: Int, params: TempoParams) {
            self.elapsed = elapsed
            self.warmupSec = params.warmupMin * 60
            self.tempoSec = params.tempoMin * 60
            self.cooldownSec = params.cooldownMin * 60

            if elapsed < warmupSec {
                name = "WARMUP"; color = .blue
                remaining = warmupSec - elapsed
                progress = Double(elapsed) / Double(max(1, warmupSec))
            } else if elapsed < warmupSec + tempoSec {
                name = "TEMPO"; color = .red
                let te = elapsed - warmupSec
                remaining = tempoSec - te
                progress = Double(te) / Double(max(1, tempoSec))
            } else {
                name = "COOLDOWN"; color = .green
                let ce = elapsed - warmupSec - tempoSec
                remaining = max(0, cooldownSec - ce)
                progress = cooldownSec > 0 ? min(1.0, Double(ce) / Double(cooldownSec)) : 1.0
            }
        }
    }

    @ViewBuilder
    private func tempoView(params: TempoParams) -> some View {
        let state = TempoPhaseState(elapsed: Int(elapsedSeconds), params: params)

        VStack(spacing: 12) {
            Text("Tempo Run")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(state.name)
                .font(.title2.weight(.black))
                .foregroundStyle(state.color)

            Text(formatSeconds(state.remaining))
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                .foregroundStyle(state.color)

            // 3-segment bar
            GeometryReader { geo in
                let total = Double(state.warmupSec + state.tempoSec + state.cooldownSec)
                let w1 = geo.size.width * Double(state.warmupSec) / total
                let w2 = geo.size.width * Double(state.tempoSec) / total
                let w3 = geo.size.width * Double(state.cooldownSec) / total

                HStack(spacing: 2) {
                    phaseSegment(width: w1, color: .blue, isActive: state.name == "WARMUP", progress: state.name == "WARMUP" ? state.progress : (state.elapsed >= state.warmupSec ? 1 : 0))
                    phaseSegment(width: w2, color: .red, isActive: state.name == "TEMPO", progress: state.name == "TEMPO" ? state.progress : (state.elapsed >= state.warmupSec + state.tempoSec ? 1 : 0))
                    phaseSegment(width: w3, color: .green, isActive: state.name == "COOLDOWN", progress: state.name == "COOLDOWN" ? state.progress : 0)
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())

            HStack {
                Text("\(params.warmupMin)m warm")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
                Spacer()
                Text("\(params.tempoMin)m tempo")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                Spacer()
                Text("\(params.cooldownMin)m cool")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }
        }
        .phaseCard()
    }

    private func phaseSegment(width: CGFloat, color: Color, isActive: Bool, progress: Double) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(color.opacity(0.2))
                .frame(width: width)
            Rectangle()
                .fill(color)
                .frame(width: width * progress)
        }
    }

    // MARK: - Intervals

    @ViewBuilder
    private func intervalView(params: IntervalParams) -> some View {
        // Simplified: each rep = effort + rest, estimate from elapsed time
        let repDuration = max(60, params.restSeconds + 60) // rough estimate: 60s effort + rest
        let totalElapsed = Int(elapsedSeconds)
        let currentRep = min(totalElapsed / repDuration, params.reps - 1)
        let timeInRep = totalElapsed % repDuration
        let isEffort = timeInRep < (repDuration - params.restSeconds)

        VStack(spacing: 12) {
            Text("Intervals")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(isEffort ? "GO" : "REST")
                .font(.title2.weight(.black))
                .foregroundStyle(isEffort ? .red : .green)

            if !isEffort {
                Text(formatSeconds(repDuration - timeInRep))
                    .font(.system(.title, design: .monospaced).weight(.bold))
                    .foregroundStyle(.green)
            }

            Text("Rep \(currentRep + 1) / \(params.reps)")
                .font(.subheadline.weight(.medium))

            if params.distancePerRep > 0 {
                Text("\(String(format: "%.0f", params.distancePerRep))m per rep")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Rep dots
            HStack(spacing: 6) {
                ForEach(0..<params.reps, id: \.self) { i in
                    Circle()
                        .fill(i < currentRep ? Color.green :
                              i == currentRep ? (isEffort ? Color.red : Color.green) :
                              Color(.systemGray4))
                        .frame(width: 10, height: 10)
                }
            }
        }
        .phaseCard()
    }

    // MARK: - Steady State

    @ViewBuilder
    private func steadyStateView(params: SteadyStateParams) -> some View {
        VStack(spacing: 8) {
            Text("Steady State")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Image(systemName: "heart.circle.fill")
                    .foregroundStyle(.red)
                Text("Target Zone \(params.targetHRZone)")
                    .font(.headline)
            }

            Text("Maintain consistent effort in Zone \(params.targetHRZone)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .phaseCard()
    }

    // MARK: - Helpers

    private func formatSeconds(_ secs: Int) -> String {
        let m = secs / 60
        let s = secs % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Phase Card Modifier

private extension View {
    func phaseCard() -> some View {
        self
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: WDS.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
    }
}
