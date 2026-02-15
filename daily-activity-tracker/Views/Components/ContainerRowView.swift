import SwiftUI

/// Expandable row for Container-type activities showing children and partial completion
struct ContainerRowView: View {
    let activity: Activity
    let todayLogs: [ActivityLog]
    let scheduleEngine: ScheduleEngineProtocol
    let today: Date
    let onCompleteChild: (Activity) -> Void
    let onSkipChild: (Activity, String) -> Void

    @State private var isExpanded = false
    @State private var showSkipSheet = false

    private static let skipReasons = ["Injury", "Weather", "Sick", "Not Feeling Well", "Other"]

    /// Children that should appear today (respecting their own schedules)
    private var todayChildren: [Activity] {
        (activity.children)
            .filter { scheduleEngine.shouldShow($0, on: today) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Partial completion score based on weighted children
    private var completionScore: Double {
        let applicable = todayChildren
        guard !applicable.isEmpty else { return 1.0 }

        let totalWeight = applicable.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 1.0 }

        let completedWeight = applicable.reduce(0.0) { sum, child in
            sum + (childCompletion(child) * child.weight)
        }
        return completedWeight / totalWeight
    }

    /// Completion fraction for a single child (0 or 1 for checkbox, proportional for cumulative)
    private func childCompletion(_ child: Activity) -> Double {
        let childLogs = todayLogs.filter { $0.activity?.id == child.id }

        switch child.type {
        case .checkbox:
            return childLogs.contains(where: { $0.status == .completed }) ? 1.0 : 0.0
        case .value:
            return childLogs.contains(where: { $0.status == .completed }) ? 1.0 : 0.0
        case .cumulative:
            let total = childLogs.filter { $0.status == .completed }.reduce(0.0) { $0 + ($1.value ?? 0) }
            let target = child.targetValue ?? 1
            return min(total / target, 1.0)
        case .container:
            return 0.0 // nested containers handled recursively in future
        }
    }

    private func isChildCompleted(_ child: Activity) -> Bool {
        childCompletion(child) >= 1.0
    }

    private func isChildSkipped(_ child: Activity) -> Bool {
        todayLogs.contains { $0.activity?.id == child.id && $0.status == .skipped }
    }

    private var doneCount: Int {
        todayChildren.filter { isChildCompleted($0) }.count
    }

    private var pendingChildren: [Activity] {
        todayChildren.filter { !isChildCompleted($0) && !isChildSkipped($0) }
    }
    
    private var completedChildren: [Activity] {
        todayChildren.filter { isChildCompleted($0) }
    }
    
    private var skippedChildren: [Activity] {
        todayChildren.filter { isChildSkipped($0) }
    }

    var body: some View {
        VStack(spacing: 4) {
            // Parent header row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: activity.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: activity.hexColor))
                        .frame(width: 28)

                    // Mini progress ring
                    ZStack {
                        Circle()
                            .stroke(Color(.systemGray5), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: completionScore)
                            .stroke(Color(hex: activity.hexColor), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 22, height: 22)

                    Text(activity.name)
                        .font(.body)
                        .foregroundStyle(completionScore >= 1.0 ? .secondary : .primary)

                    Spacer()

                    Text("\(doneCount)/\(todayChildren.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contextMenu {
                if !pendingChildren.isEmpty {
                    Button {
                        pendingChildren
                            .filter { $0.type == .checkbox }
                            .forEach { onCompleteChild($0) }
                    } label: {
                        Label("Complete All", systemImage: "checkmark.circle")
                    }

                    Button {
                        showSkipSheet = true
                    } label: {
                        Label("Skip All Pending", systemImage: "forward")
                    }
                }
                
                if !completedChildren.isEmpty {
                    Button(role: .destructive) {
                        completedChildren.forEach { onCompleteChild($0) }
                    } label: {
                        Label("Undo All", systemImage: "arrow.uturn.backward")
                    }
                }
            }
            .confirmationDialog("Reason for skipping", isPresented: $showSkipSheet) {
                ForEach(Self.skipReasons, id: \.self) { reason in
                    Button(reason) {
                        pendingChildren.forEach { onSkipChild($0, reason) }
                    }
                }
                Button("Cancel", role: .cancel) { }
            }

            // Expanded children
            if isExpanded {
                VStack(spacing: 4) {
                    // Pending children
                    ForEach(pendingChildren) { child in
                        HStack {
                            Rectangle()
                                .fill(Color(hex: activity.hexColor).opacity(0.3))
                                .frame(width: 2)
                                .padding(.leading, 20)

                            childRow(child)
                        }
                    }
                    
                    // Completed children
                    ForEach(completedChildren) { child in
                        HStack {
                            Rectangle()
                                .fill(Color.green.opacity(0.3))
                                .frame(width: 2)
                                .padding(.leading, 20)

                            childRow(child)
                        }
                    }
                    
                    // Skipped children
                    if !skippedChildren.isEmpty {
                        HStack {
                            Rectangle()
                                .fill(Color.orange.opacity(0.3))
                                .frame(width: 2)
                                .padding(.leading, 20)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "forward.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                    Text("Skipped (\(skippedChildren.count))")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                
                                ForEach(skippedChildren) { child in
                                    HStack(spacing: 8) {
                                        Image(systemName: "forward.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.orange)
                                        Text(child.name)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .strikethrough(true, color: .secondary)
                                        
                                        Spacer()
                                        
                                        if let reason = skipReason(for: child) {
                                            Text(reason)
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(.orange.opacity(0.15))
                                                .foregroundStyle(.orange)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 10)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }

                    // "Mark All Done" shortcut — only if there are still pending children
                    if !pendingChildren.isEmpty {
                        Button {
                            todayChildren
                                .filter { !isChildCompleted($0) && !isChildSkipped($0) && $0.type == .checkbox }
                                .forEach { onCompleteChild($0) }
                        } label: {
                            Text("Mark All Done")
                                .font(.caption)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color(hex: activity.hexColor).opacity(0.15))
                                .foregroundStyle(Color(hex: activity.hexColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(.leading, 28)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func childRow(_ child: Activity) -> some View {
        switch child.type {
        case .checkbox:
            ActivityRowView(
                activity: child,
                isCompleted: isChildCompleted(child),
                isSkipped: isChildSkipped(child),
                onComplete: { onCompleteChild(child) },
                onSkip: { reason in onSkipChild(child, reason) }
            )
        default:
            // Value/Cumulative children rendered as checkbox rows for P1
            ActivityRowView(
                activity: child,
                isCompleted: isChildCompleted(child),
                isSkipped: isChildSkipped(child),
                onComplete: { onCompleteChild(child) },
                onSkip: { reason in onSkipChild(child, reason) }
            )
        }
    }
    
    private func skipReason(for child: Activity) -> String? {
        todayLogs.first(where: { $0.activity?.id == child.id && $0.status == .skipped })?.skipReason
    }
}
