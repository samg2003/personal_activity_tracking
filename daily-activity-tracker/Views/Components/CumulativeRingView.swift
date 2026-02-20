import SwiftUI

/// Compact ring for cumulative items in the All Day section
struct CumulativeRingView: View {
    let activity: Activity
    let currentValue: Double
    let onAdd: (Double) -> Void
    var isSkipped: Bool = false
    var onSkip: ((String) -> Void)?
    var onShowLogs: (() -> Void)?

    @State private var showInput = false
    @State private var inputText = ""
    @State private var showSkipSheet = false
    @State private var addScale: CGFloat = 1.0

    private var target: Double { activity.targetValue ?? 1 }
    private var progress: Double { min(currentValue / target, 1.0) }
    private var unitLabel: String { activity.unit ?? "" }
    private var color: Color { Color(hex: activity.hexColor) }
    private var isDone: Bool { progress >= 1.0 }

    var body: some View {
        rowContent
            .padding(.vertical, 10)
            .background(rowBackground)
            .opacity(isDone ? 0.7 : 1.0)
            .onTapGesture { showInput = true }
            .contextMenu { contextMenuItems }
            .swipeActions(edge: .leading) { swipeItems }
            .confirmationDialog("Reason for skipping", isPresented: $showSkipSheet) {
                ForEach(SkipReasons.defaults, id: \.self) { reason in
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
                Text("Current: \(currentValue.cleanDisplay) / \(target.cleanDisplay) \(unitLabel)")
            }
    }

    // MARK: - Sub-views

    private var rowContent: some View {
        HStack(spacing: 0) {
            accentBar
            innerContent
                .padding(.leading, 10)
                .padding(.trailing, 14)
        }
    }

    private var accentBar: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isSkipped ? Color.orange : color)
            .frame(width: 4)
            .padding(.vertical, 6)
    }

    private var innerContent: some View {
        HStack(spacing: 12) {
            iconBadge
            nameAndProgress
            addButton
        }
    }

    private var iconBadge: some View {
        Image(systemName: activity.icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isDone ? .secondary : color)
            .frame(width: 30, height: 30)
            .background(
                Circle()
                    .fill(isDone ? Color(.systemGray5) : color.opacity(0.12))
            )
    }

    private var nameAndProgress: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(activity.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Spacer()

                Text("\(currentValue.cleanDisplay)/\(target.cleanDisplay) \(unitLabel)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isDone ? .green : .secondary)
            }

            progressBar
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(height: 8)

                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.7), color],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(geo.size.width * progress, 0), height: 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: progress)
            }
        }
        .frame(height: 8)
    }

    private var addButton: some View {
        Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                addScale = 1.3
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.2)) { addScale = 1.0 }
            }
            showInput = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(color)
                .scaleEffect(addScale)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSkipped {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.08))
                .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
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

        if onSkip != nil {
            Button {
                showSkipSheet = true
            } label: {
                Label("Skip", systemImage: "forward")
            }
        }
    }

    @ViewBuilder
    private var swipeItems: some View {
        if onSkip != nil {
            Button { showSkipSheet = true } label: {
                Label("Skip", systemImage: "forward.fill")
            }
            .tint(.orange)
        }
    }
}
