import SwiftUI

struct ProgressRingView: View {
    let progress: Double
    var lineWidth: CGFloat = 10
    var size: CGFloat = 100

    private var clampedProgress: Double { min(max(progress, 0), 1) }

    private var ringColor: Color {
        if clampedProgress >= 0.8 { return .green }
        if clampedProgress >= 0.5 { return .yellow }
        return .orange
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color(.systemGray5), lineWidth: lineWidth)

            // Fill
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: clampedProgress)

            // Percentage text
            VStack(spacing: 2) {
                Text("\(Int(clampedProgress * 100))%")
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("Done")
                    .font(.system(size: size * 0.12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    VStack(spacing: 20) {
        ProgressRingView(progress: 0.72)
        ProgressRingView(progress: 0.3, size: 60)
    }
    .padding()
    .preferredColorScheme(.dark)
}
