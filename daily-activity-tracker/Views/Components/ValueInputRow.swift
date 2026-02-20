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
    private var accentColor: Color { Color(hex: activity.hexColor) }

    var body: some View {
        HStack(spacing: 0) {
            // Colored accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(accentColor)
                .frame(width: 4)
                .padding(.vertical, 6)

            HStack(spacing: 12) {
                // Icon badge
                Image(systemName: activity.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isLogged ? .secondary : accentColor)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(isLogged ? Color(.systemGray5) : accentColor.opacity(0.12))
                    )

                // Status indicator
                Image(systemName: isLogged ? "checkmark.circle.fill" : "pencil.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isLogged ? .green : accentColor)

                Text(activity.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isLogged ? .secondary : .primary)

                Spacer()

                // Logged value or prompt
                if let val = currentValue {
                    Text("\(val.cleanDisplay) \(unitLabel)")
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(accentColor.opacity(0.12))
                        .clipShape(Capsule())
                } else {
                    Text("Log \(unitLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let onTakePhoto {
                    Button {
                        onTakePhoto()
                    } label: {
                        Image(systemName: "camera")
                            .font(.system(size: 14))
                            .foregroundStyle(accentColor.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 14)
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(isLogged ? 0.02 : 0.06), radius: 6, y: 3)
        )
        .opacity(isLogged ? 0.65 : 1.0)
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
