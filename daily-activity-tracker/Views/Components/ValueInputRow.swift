import SwiftUI

/// Row for Value-type activities (log a single number)
struct ValueInputRow: View {
    let activity: Activity
    let currentValue: Double?
    let onLog: (Double) -> Void

    @State private var showInput = false
    @State private var inputText = ""

    private var unitLabel: String { activity.unit ?? "" }
    private var isLogged: Bool { currentValue != nil }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: activity.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: activity.hexColor))
                .frame(width: 28)

            // Status indicator
            Image(systemName: isLogged ? "checkmark.circle.fill" : "pencil.circle")
                .font(.system(size: 22))
                .foregroundStyle(isLogged ? .green : Color(hex: activity.hexColor))

            Text(activity.name)
                .font(.body)
                .foregroundStyle(isLogged ? .secondary : .primary)

            Spacer()

            // Logged value display or prompt
            if let val = currentValue {
                Text("\(formatValue(val)) \(unitLabel)")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color(hex: activity.hexColor))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: activity.hexColor).opacity(0.15))
                    .clipShape(Capsule())
            } else {
                Text("Log \(unitLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            if let val = currentValue { inputText = formatValue(val) }
            showInput = true
        }
        .alert("Log \(activity.name)", isPresented: $showInput) {
            TextField(unitLabel.isEmpty ? "Value" : unitLabel, text: $inputText)
                .keyboardType(.decimalPad)
            Button("Save") {
                if let val = Double(inputText) {
                    onLog(val)
                    inputText = ""
                }
            }
            Button("Cancel", role: .cancel) { inputText = "" }
        }
    }

    private func formatValue(_ val: Double) -> String {
        val.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", val)
            : String(format: "%.1f", val)
    }
}
