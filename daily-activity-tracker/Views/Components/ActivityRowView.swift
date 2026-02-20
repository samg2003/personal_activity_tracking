import SwiftUI

struct ActivityRowView: View {
    let activity: Activity
    let isCompleted: Bool
    let isSkipped: Bool
    let onComplete: () -> Void
    let onSkip: (String) -> Void

    @State private var showSkipSheet = false
    @State private var checkScale: CGFloat = 1.0

    private var accentColor: Color { Color(hex: activity.hexColor) }

    var body: some View {
        rowContent
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(isCompleted ? 0.02 : 0.06), radius: 6, y: 3)
            )
            .opacity(isCompleted ? 0.65 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            // UX-2: Tap anywhere on the row to toggle completion
            .onTapGesture {
                guard !isSkipped else { return }
                triggerComplete()
            }
            .contextMenu { contextMenuContent }
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
                ForEach(SkipReasons.defaults, id: \.self) { reason in
                    Button(reason) { onSkip(reason) }
                }
                Button("Cancel", role: .cancel) { }
            }
    }

    // MARK: - Sub-views

    private var rowContent: some View {
        HStack(spacing: 0) {
            // Colored accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(isSkipped ? Color.orange : accentColor)
                .frame(width: 4)
                .padding(.vertical, 6)

            HStack(spacing: 12) {
                // Icon badge
                Image(systemName: activity.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isCompleted ? .secondary : accentColor)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(isCompleted ? Color(.systemGray5) : accentColor.opacity(0.12))
                    )

                // Animated checkbox (visual indicator only — tapping anywhere works)
                checkboxIndicator

                // Activity name
                Text(activity.name)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(isCompleted, color: .secondary.opacity(0.5))
                    .foregroundStyle(isCompleted ? .secondary : .primary)

                Spacer()

                // Category pill
                if let cat = activity.category {
                    Text(cat.name)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(hex: cat.hexColor).opacity(0.15))
                        .foregroundStyle(Color(hex: cat.hexColor))
                        .clipShape(Capsule())
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 14)
        }
    }

    private var checkboxIndicator: some View {
        ZStack {
            Circle()
                .stroke(isCompleted ? Color.clear : Color(.systemGray3), lineWidth: 2)
                .frame(width: 24, height: 24)

            if isCompleted {
                Circle()
                    .fill(.green)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(checkScale)
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        if isCompleted {
            Button(role: .destructive) {
                onComplete()
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

    // MARK: - Helpers

    private func triggerComplete() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            checkScale = 1.3
            onComplete()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.2)) { checkScale = 1.0 }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
