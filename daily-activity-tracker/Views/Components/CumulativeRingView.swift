import SwiftUI

/// Compact ring for cumulative items in the All Day section
struct CumulativeRingView: View {
    let activity: Activity
    let currentValue: Double
    let onAdd: (Double) -> Void
    var isSkipped: Bool = false
    var onSkip: ((String) -> Void)?
    var onShowLogs: (() -> Void)?

    private static let skipReasons = ["Injury", "Weather", "Sick", "Gym Closed", "Other"]

    @State private var showInput = false
    @State private var inputText = ""
    @State private var showSkipSheet = false

    private var target: Double { activity.targetValue ?? 1 }
    private var progress: Double { min(currentValue / target, 1.0) }
    private var unitLabel: String { activity.unit ?? "" }
    private var color: Color { Color(hex: activity.hexColor) }

    var body: some View {
        HStack(spacing: 12) {
            // Activity icon
            Image(systemName: activity.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24)

            // Name + progress bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(activity.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text("\(formatValue(currentValue))/\(formatValue(target)) \(unitLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Flat progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(.systemGray5))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(width: geo.size.width * progress, height: 6)
                            .animation(.easeInOut(duration: 0.3), value: progress)
                    }
                }
                .frame(height: 6)
            }

            // Quick add button
            Button {
                showInput = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(color)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(isSkipped ? Color.orange.opacity(0.15) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { showInput = true }
        .contextMenu {
            Button {
                showInput = true
            } label: {
                Label("Add Entry", systemImage: "plus.circle")
            }
            
            if let onShowLogs {
                Button {
                    onShowLogs()
                } label: {
                    Label("View Entries", systemImage: "list.bullet")
                }
            }

            if let onSkip {
                Button {
                    showSkipSheet = true
                } label: {
                    Label("Skip", systemImage: "forward")
                }
            }
        }
        .swipeActions(edge: .leading) {
            if onSkip != nil {
                Button { showSkipSheet = true } label: {
                    Label("Skip", systemImage: "forward.fill")
                }
                .tint(.orange)
            }
        }
        .confirmationDialog("Reason for skipping", isPresented: $showSkipSheet) {
            ForEach(Self.skipReasons, id: \.self) { reason in
                Button(reason) { onSkip?(reason) }
            }
            Button("Cancel", role: .cancel) { }
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
