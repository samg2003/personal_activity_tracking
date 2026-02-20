import SwiftUI

/// Data-driven insight card showing best streak, biggest metric win, and behind count
struct InsightSummaryCard: View {
    let bestStreak: (name: String, count: Int)?
    let biggestWin: (name: String, delta: String)?
    let behindCount: Int

    var body: some View {
        VStack(spacing: 12) {
            // Headline row
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

            // Behind schedule nudge
            if behindCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text("\(behindCount) activit\(behindCount == 1 ? "y" : "ies") behind schedule")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                    Text("All activities on track this week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: WDS.cardRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
        )
    }

    private func statPill(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
