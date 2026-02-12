import SwiftUI

/// Floating undo toast with auto-dismiss and action callback
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    @Binding var isPresented: Bool
    @State private var opacity: Double = 0
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        if isPresented {
            HStack(spacing: 12) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                Button {
                    onUndo()
                    dismissToast()
                } label: {
                    Text("Undo")
                        .font(.subheadline.bold())
                        .foregroundStyle(.yellow)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.systemGray2).opacity(0.85))
                    )
            )
            .padding(.horizontal, 16)
            .opacity(opacity)
            .offset(y: opacity > 0 ? 0 : 20)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) {
                    opacity = 1
                }
                scheduleAutoDismiss()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func scheduleAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await MainActor.run { dismissToast() }
        }
    }

    private func dismissToast() {
        withAnimation(.easeIn(duration: 0.2)) {
            opacity = 0
        }
        // Delay removal until animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isPresented = false
        }
    }
}

// MARK: - View Modifier for easy integration

struct UndoToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let onUndo: () -> Void

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content

            UndoToast(
                message: message,
                onUndo: onUndo,
                isPresented: $isPresented
            )
            .padding(.bottom, 8)
        }
    }
}

extension View {
    func undoToast(isPresented: Binding<Bool>, message: String, onUndo: @escaping () -> Void) -> some View {
        modifier(UndoToastModifier(isPresented: isPresented, message: message, onUndo: onUndo))
    }
}
