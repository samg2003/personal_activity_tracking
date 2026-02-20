import SwiftUI

/// Data-driven insight card — gradient hero banner with animated stats
struct InsightSummaryCard: View {
    let bestStreak: (name: String, count: Int)?
    let biggestWin: (name: String, delta: String)?
    let behindCount: Int

    var body: some View {
        VStack(spacing: 0) {
            // Gradient hero area
            statsRow
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: WDS.cardRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0x10B981), Color(hex: 0x0D9488)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                )

            // Behind-schedule nudge strip
            nudgeStrip
        }
        .clipShape(RoundedRectangle(cornerRadius: WDS.cardRadius, style: .continuous))
        .shadow(color: Color(hex: 0x10B981).opacity(0.15), radius: 10, y: 5)
    }

    // MARK: - Sub-views

    private var statsRow: some View {
        HStack(spacing: 16) {
            if let streak = bestStreak, streak.count > 0 {
                statPill(
                    icon: "flame.fill",
                    iconColor: .orange,
                    label: streak.name,
                    value: "\(streak.count)d"
                )
            }

            if let win = biggestWin {
                statPill(
                    icon: "arrow.up.right",
                    iconColor: .green,
                    label: win.name,
                    value: win.delta
                )
            }
        }
    }

    @ViewBuilder
    private var nudgeStrip: some View {
        if behindCount > 0 {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text("\(behindCount) activit\(behindCount == 1 ? "y" : "ies") behind schedule")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text("All activities on track this week")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    private func statPill(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            // Circular icon background
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(.white.opacity(0.2))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
