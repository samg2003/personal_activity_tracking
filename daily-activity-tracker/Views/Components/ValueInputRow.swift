import SwiftUI

/// Row for Value-type activities (log a single number)
struct ValueInputRow: View {
    let activity: Activity
    let currentValue: Double?
    let onLog: (Double) -> Void
    var onSkip: ((String) -> Void)?
    var onRemove: (() -> Void)?
    var onShowLogs: (() -> Void)?
    var onTakePhoto: (() -> Void)?

    @State private var showInput = false
    @State private var inputText = ""
    @State private var showSkipSheet = false



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
                Text("\(val.cleanDisplay) \(unitLabel)")
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

            // Camera shortcut for photo-enabled activities
            if let onTakePhoto {
                Button {
                    onTakePhoto()
                } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: activity.hexColor).opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            if let val = currentValue { inputText = val.cleanDisplay }
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
        .contextMenu {
            Button {
                if let val = currentValue { inputText = val.cleanDisplay }
                showInput = true
            } label: {
                Label("Edit Value", systemImage: "pencil")
            }
            
            if let onShowLogs {
                Button {
                    onShowLogs()
                } label: {
                    Label("View Entries", systemImage: "list.bullet")
                }
            }

            if currentValue != nil, let onRemove, onShowLogs == nil {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Clear Value", systemImage: "trash")
                }
            }

            if let onTakePhoto {
                Button {
                    onTakePhoto()
                } label: {
                    Label("Add Photo", systemImage: "camera")
                }
            }

            if let onSkip, !isLogged {
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
            ForEach(SkipReasons.defaults, id: \.self) { reason in
                Button(reason) { onSkip?(reason) }
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}
