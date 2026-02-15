import SwiftUI

struct ActivityRowView: View {
    let activity: Activity
    let isCompleted: Bool
    let isSkipped: Bool
    let onComplete: () -> Void
    let onSkip: (String) -> Void

    @State private var showSkipSheet = false

    private static let skipReasons = ["Injury", "Weather", "Sick", "Gym Closed", "Other"]

    var body: some View {
        HStack(spacing: 14) {
            // Activity icon
            Image(systemName: activity.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: activity.hexColor))
                .frame(width: 28)

            // Checkbox circle
            Button {
                if !isSkipped {
                    withAnimation(.spring(response: 0.3)) {
                        onComplete()
                    }
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
            } label: {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isCompleted ? .green : Color(.systemGray3))
            }
            .buttonStyle(.plain)

            // Activity name
            Text(activity.name)
                .font(.body)
                .strikethrough(isCompleted, color: .secondary)
                .foregroundStyle(isCompleted ? .secondary : .primary)

            Spacer()

            // Category badge
            if let cat = activity.category {
                Text(cat.name)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: cat.hexColor).opacity(0.2))
                    .foregroundStyle(Color(hex: cat.hexColor))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            if isCompleted {
                Button(role: .destructive) {
                    onComplete() // Toggles off
                } label: {
                    Label("Undo Completion", systemImage: "arrow.uturn.backward")
                }
            } else {
                Button {
                    onComplete()
                } label: {
                    Label("Complete", systemImage: "checkmark")
                }
                
                Button {
                    showSkipSheet = true
                } label: {
                    Label("Skip", systemImage: "forward")
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button {
                withAnimation { onComplete() }
            } label: {
                Label("Done", systemImage: "checkmark")
            }
            .tint(.green)
        }
        .swipeActions(edge: .leading) {
            Button { showSkipSheet = true } label: {
                Label("Skip", systemImage: "forward.fill")
            }
            .tint(.orange)
        }
        .confirmationDialog("Reason for skipping", isPresented: $showSkipSheet) {
            ForEach(Self.skipReasons, id: \.self) { reason in
                Button(reason) { onSkip(reason) }
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}
