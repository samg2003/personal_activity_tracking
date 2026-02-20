import SwiftUI

/// Daily completion progress — large animated circular ring with center stats
struct ProgressRingView: View {
    let progress: Double

    @State private var animatedProgress: Double = 0
    @State private var glowPulse = false

    private var clampedProgress: Double { min(max(progress, 0), 1) }
    private var isDone: Bool { clampedProgress >= 1.0 }

    private var ringGradient: AngularGradient {
        let colors: [Color] = isDone
            ? [.green, Color(hex: 0x10B981), .green]
            : clampedProgress >= 0.5
                ? [Color(hex: 0x10B981), Color(hex: 0x34D399), Color(hex: 0x10B981)]
                : [.orange, Color(hex: 0xF59E0B), .orange]
        return AngularGradient(
            gradient: Gradient(colors: colors),
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270)
        )
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 10)

            // Fill
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(ringGradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Glow when done
            if isDone {
                Circle()
                    .stroke(Color.green.opacity(glowPulse ? 0.3 : 0.1), lineWidth: 14)
                    .blur(radius: 6)
                    .rotationEffect(.degrees(-90))
            }

            // Center content
            VStack(spacing: 2) {
                Text("\(Int(clampedProgress * 100))%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(isDone ? .green : .primary)
                    .contentTransition(.numericText())

                if isDone {
                    Text("All done! 🎉")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("completed")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 120, height: 120)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                animatedProgress = clampedProgress
            }
            if isDone {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    glowPulse = true
                }
            }
        }
        .onChange(of: progress) { _, newVal in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                animatedProgress = min(max(newVal, 0), 1)
            }
            if min(max(newVal, 0), 1) >= 1.0 && !glowPulse {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    glowPulse = true
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ProgressRingView(progress: 0.72)
        ProgressRingView(progress: 0.3)
        ProgressRingView(progress: 1.0)
    }
    .padding()
    .preferredColorScheme(.dark)
}
