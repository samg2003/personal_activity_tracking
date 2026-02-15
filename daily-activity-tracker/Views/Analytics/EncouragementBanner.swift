import SwiftUI

/// Encouragement banner with streak highlights and "most improved" callout
struct EncouragementBanner: View {
    let topStreak: (name: String, count: Int)?
    let mostImproved: String?
    let overallScore: Double

    private var message: String {
        // Smart Suggestion Logic
        let hour = Calendar.current.component(.hour, from: Date())
        
        // Morning (6-11 AM)
        if hour >= 6 && hour < 12 {
            if overallScore < 0.3 { return "Start small. A 5-minute win clears the path 🌅" }
            return "Good morning! Attack the day ☀️"
        }
        
        // Afternoon (12-5 PM)
        if hour >= 12 && hour < 17 {
            if overallScore < 0.5 { return "Still plenty of time to turn the day around 🚀" }
            return "Keep the momentum going! 🔥"
        }
        
        // Evening (5-9 PM)
        if hour >= 17 && hour < 21 {
            return "Evening routine coming up. Finish strong! 🌙"
        }
        
        // Night (9 PM+)
        if overallScore >= 0.9 { return "You crushed it today! Rest well 😴" }
        return "Reflect and recharge. Tomorrow is a new start 🌱"
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
