import SwiftUI

/// Compact ring for cumulative items in the All Day section
struct CumulativeRingView: View {
    let activity: Activity
    let currentValue: Double
    let onAdd: (Double) -> Void

    @State private var showInput = false
    @State private var inputText = ""

    private var target: Double { activity.targetValue ?? 1 }
    private var progress: Double { min(currentValue / target, 1.0) }
    private var unitLabel: String { activity.unit ?? "" }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color(hex: activity.hexColor),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: progress)

                VStack(spacing: 0) {
                    Text(formatValue(currentValue))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    if !unitLabel.isEmpty {
                        Text(unitLabel)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 60, height: 60)
            .onTapGesture { showInput = true }

            HStack(spacing: 4) {
                Image(systemName: activity.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: activity.hexColor))
                Text(activity.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
        }
        .alert("Add \(activity.name)", isPresented: $showInput) {
            TextField("Amount", text: $inputText)
                .keyboardType(.decimalPad)
            Button("Add") {
                if let val = Double(inputText), val > 0 {
                    onAdd(val)
                    inputText = ""
                }
            }
            Button("Cancel", role: .cancel) { inputText = "" }
        } message: {
            Text("Current: \(formatValue(currentValue)) / \(formatValue(target)) \(unitLabel)")
        }
    }

    private func formatValue(_ val: Double) -> String {
        val.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", val)
            : String(format: "%.1f", val)
    }
}
