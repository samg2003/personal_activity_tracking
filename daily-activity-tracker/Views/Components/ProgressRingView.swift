import SwiftUI

/// Daily completion progress bar — thick, elegant horizontal bar with percentage
struct ProgressRingView: View {
    let progress: Double
    
    private var clampedProgress: Double { min(max(progress, 0), 1) }
    
    private var barColor: Color {
        if clampedProgress >= 0.8 { return .green }
        if clampedProgress >= 0.5 { return .yellow }
        return .orange
    }
    
    private var gradient: LinearGradient {
        LinearGradient(
            colors: [barColor.opacity(0.8), barColor],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Today's Progress")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(Int(clampedProgress * 100))%")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(barColor)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(.systemGray5))
                    
                    // Fill
                    RoundedRectangle(cornerRadius: 7)
                        .fill(gradient)
                        .frame(width: max(geo.size.width * clampedProgress, 0))
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: clampedProgress)
                }
            }
            .frame(height: 14)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    VStack(spacing: 12) {
        ProgressRingView(progress: 0.72)
        ProgressRingView(progress: 0.3)
        ProgressRingView(progress: 1.0)
    }
    .padding()
    .preferredColorScheme(.dark)
}
