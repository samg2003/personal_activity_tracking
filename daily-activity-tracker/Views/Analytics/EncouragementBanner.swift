import SwiftUI

/// Encouragement banner with streak highlights and "most improved" callout
struct EncouragementBanner: View {
    let topStreak: (name: String, count: Int)?
    let mostImproved: String?
    let overallScore: Double

    private var message: String {
        if overallScore >= 0.9 { return "Outstanding consistency! Keep it up! 🏆" }
        if overallScore >= 0.7 { return "Great momentum! You're building solid habits 💪" }
        if overallScore >= 0.5 { return "Halfway there! Every check counts 🎯" }
        return "Small steps lead to big changes. Start today! 🌱"
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(message)
                .font(.subheadline.bold())
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                if let streak = topStreak, streak.count > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("\(streak.name): \(streak.count)d")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let improved = mostImproved {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.green)
                        Text("Most improved: \(improved)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.08),
                    Color.green.opacity(0.06),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
