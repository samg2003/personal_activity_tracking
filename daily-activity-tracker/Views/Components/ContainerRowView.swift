import SwiftUI

/// Expandable row for Container-type activities showing children and partial completion
struct ContainerRowView: View {
    let activity: Activity
    let todayLogs: [ActivityLog]
    let allLogs: [ActivityLog]
    let scheduleEngine: ScheduleEngineProtocol
    let today: Date
    let allActivities: [Activity]
    let onCompleteChild: (Activity, TimeSlot?) -> Void
    let onSkipChild: (Activity, String, TimeSlot?) -> Void

    /// When set, only show children applicable to this time slot
    var slotFilter: TimeSlot? = nil

    @State private var isExpanded = false
    @State private var showSkipSheet = false



    /// Children that should appear today, including carry-forward from missed days
    private var todayChildren: [Activity] {
        let allChildren = activity.historicalChildren(on: today, from: allActivities)
        // Normally scheduled children
        var base = allChildren.filter { scheduleEngine.shouldShow($0, on: today) }

        // Add carry-forward children (missed from previous scheduled days)
        let baseIDs = Set(base.map { $0.id })
        let carryForward = allChildren.filter { child in
            !baseIDs.contains(child.id)
            && !child.isArchived
            && scheduleEngine.carriedForwardDate(for: child, on: today, logs: allLogs) != nil
        }
        base.append(contentsOf: carryForward)

        let filtered: [Activity]
        if let slot = slotFilter {
            filtered = base.filter { child in
                if child.isMultiSession {
                    return child.timeSlots.contains(slot)
                }
                return (child.timeWindow?.slot ?? .morning) == slot
            }
        } else {
            filtered = base
        }

        return filtered.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func isChildCarriedForward(_ child: Activity) -> Bool {
        scheduleEngine.carriedForwardDate(for: child, on: today, logs: allLogs) != nil
    }

    /// Partial completion score based on children (equal weight)
    private var completionScore: Double {
        let applicable = todayChildren
        guard !applicable.isEmpty else { return 1.0 }

        let completedSum = applicable.reduce(0.0) { sum, child in
            sum + childCompletion(child)
        }
        return completedSum / Double(applicable.count)
    }

    /// Completion fraction for a single child (0 or 1 for checkbox, proportional for cumulative)
    private func childCompletion(_ child: Activity) -> Double {
        let childLogs = todayLogs.filter { $0.activity?.id == child.id }

        switch child.type {
        case .checkbox, .metric:
            if child.isMultiSession {
                // Check per-slot if filtered, otherwise check all sessions
                if let slot = slotFilter {
                    return childLogs.contains(where: { $0.status == .completed && $0.timeSlot == slot }) ? 1.0 : 0.0
                }
                let total = child.timeSlots.count
                guard total > 0 else { return 0 }
                let done = child.timeSlots.filter { slot in
                    childLogs.contains(where: { $0.status == .completed && $0.timeSlot == slot })
                }.count
                return Double(done) / Double(total)
            }
            return childLogs.contains(where: { $0.status == .completed }) ? 1.0 : 0.0
        case .value:
            if child.isMultiSession {
                if let slot = slotFilter {
                    return childLogs.contains(where: { $0.status == .completed && $0.timeSlot == slot }) ? 1.0 : 0.0
                }
                let total = child.timeSlots.count
                guard total > 0 else { return 0 }
                let done = child.timeSlots.filter { slot in
                    childLogs.contains(where: { $0.status == .completed && $0.timeSlot == slot })
                }.count
                return Double(done) / Double(total)
            }
            return childLogs.contains(where: { $0.status == .completed }) ? 1.0 : 0.0
        case .cumulative:
            let total = childLogs.filter { $0.status == .completed }.reduce(0.0) { $0 + ($1.value ?? 0) }
            let target = child.targetValue ?? 1
            return min(total / target, 1.0)
        case .container:
            return 0.0
        }
    }

    private func isChildCompleted(_ child: Activity) -> Bool {
        childCompletion(child) >= 1.0
    }

    /// Whether a specific session of a child is completed
    private func isChildSessionCompleted(_ child: Activity, slot: TimeSlot) -> Bool {
        todayLogs.contains { $0.activity?.id == child.id && $0.status == .completed && $0.timeSlot == slot }
    }

    /// Whether a specific session of a child is skipped
    private func isChildSessionSkipped(_ child: Activity, slot: TimeSlot) -> Bool {
        todayLogs.contains { $0.activity?.id == child.id && $0.status == .skipped && $0.timeSlot == slot }
    }

    private func isChildFullySkipped(_ child: Activity) -> Bool {
        let childLogs = todayLogs.filter { $0.activity?.id == child.id }
        if child.isMultiSession {
            let nonCompleted = child.timeSlots.filter { slot in
                !childLogs.contains(where: { $0.status == .completed && $0.timeSlot == slot })
            }
            return !nonCompleted.isEmpty && nonCompleted.allSatisfy { slot in
                childLogs.contains(where: { $0.status == .skipped && $0.timeSlot == slot })
            }
        }
        return childLogs.contains { $0.status == .skipped }
    }

    /// Count of completed sessions (not just fully-completed children)
    private var doneCount: Int {
        todayChildren.reduce(0) { sum, child in
            if child.isMultiSession {
                let slotsToCount = slotFilter.map { [$0] } ?? child.timeSlots
                return sum + slotsToCount.filter { isChildSessionCompleted(child, slot: $0) }.count
            }
            return sum + (isChildCompleted(child) ? 1 : 0)
        }
    }

    /// Total sessions count (not just children count)
    private var totalCount: Int {
        todayChildren.reduce(0) { sum, child in
            if child.isMultiSession {
                let slotsToCount = slotFilter.map { [$0] } ?? child.timeSlots
                return sum + slotsToCount.count
            }
            return sum + 1
        }
    }

    private var pendingChildren: [Activity] {
        todayChildren.filter { child in
            if child.isMultiSession {
                let slotsToCheck = slotFilter.map { [$0] } ?? child.timeSlots
                return slotsToCheck.contains { slot in
                    !isChildSessionCompleted(child, slot: slot) && !isChildSessionSkipped(child, slot: slot)
                }
            }
            return !isChildCompleted(child) && !isChildFullySkipped(child)
        }
    }

    private var completedChildren: [Activity] {
        todayChildren.filter { child in
            if child.isMultiSession {
                let slotsToCheck = slotFilter.map { [$0] } ?? child.timeSlots
                return slotsToCheck.contains { isChildSessionCompleted(child, slot: $0) }
            }
            return isChildCompleted(child)
        }
    }

    private var skippedChildren: [Activity] {
        todayChildren.filter { child in
            if child.isMultiSession {
                let slotsToCheck = slotFilter.map { [$0] } ?? child.timeSlots
                return slotsToCheck.contains { slot in
                    isChildSessionSkipped(child, slot: slot) && !isChildSessionCompleted(child, slot: slot)
                }
            }
            return isChildFullySkipped(child) && !isChildCompleted(child)
        }
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

                    Text("\(doneCount)/\(totalCount)")
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
                        for child in pendingChildren.filter({ $0.type == .checkbox }) {
                            if child.isMultiSession {
                                let slotsToComplete = (slotFilter.map { [$0] } ?? child.timeSlots)
                                    .filter { !isChildSessionCompleted(child, slot: $0) && !isChildSessionSkipped(child, slot: $0) }
                                for slot in slotsToComplete {
                                    onCompleteChild(child, slot)
                                }
                            } else {
                                onCompleteChild(child, nil)
                            }
                        }
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
                        for child in completedChildren {
                            if child.isMultiSession {
                                let slotsToUndo = (slotFilter.map { [$0] } ?? child.timeSlots)
                                    .filter { isChildSessionCompleted(child, slot: $0) }
                                for slot in slotsToUndo {
                                    onCompleteChild(child, slot)
                                }
                            } else {
                                onCompleteChild(child, nil)
                            }
                        }
                    } label: {
                        Label("Undo All", systemImage: "arrow.uturn.backward")
                    }
                }
            }
            .confirmationDialog("Reason for skipping", isPresented: $showSkipSheet) {
                ForEach(SkipReasons.defaults, id: \.self) { reason in
                    Button(reason) {
                        for child in pendingChildren {
                            if child.isMultiSession {
                                let slotsToSkip = (slotFilter.map { [$0] } ?? child.timeSlots)
                                    .filter { !isChildSessionCompleted(child, slot: $0) && !isChildSessionSkipped(child, slot: $0) }
                                for slot in slotsToSkip {
                                    onSkipChild(child, reason, slot)
                                }
                            } else {
                                onSkipChild(child, reason, nil)
                            }
                        }
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
                                .fill(isChildCarriedForward(child)
                                      ? Color.red.opacity(0.5)
                                      : Color(hex: activity.hexColor).opacity(0.3))
                                .frame(width: 2)
                                .padding(.leading, 20)

                            childRow(child)
                                .overlay(alignment: .topTrailing) {
                                    if let dueDate = scheduleEngine.carriedForwardDate(for: child, on: today, logs: allLogs),
                                       !isChildCompleted(child), !isChildSkipped(child) {
                                        Text("⏳ Due \(dueDate.shortWeekday)")
                                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.red)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.red.opacity(0.12))
                                            .clipShape(Capsule())
                                            .offset(y: -2)
                                    }
                                }
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
                            for child in todayChildren.filter({ !isChildCompleted($0) && !isChildFullySkipped($0) && $0.type != .container }) {
                                if child.isMultiSession {
                                    let slotsToComplete = (slotFilter.map { [$0] } ?? child.timeSlots)
                                        .filter { !isChildSessionCompleted(child, slot: $0) && !isChildSessionSkipped(child, slot: $0) }
                                    for slot in slotsToComplete {
                                        onCompleteChild(child, slot)
                                    }
                                } else {
                                    onCompleteChild(child, nil)
                                }
                            }
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
        let completed: Bool
        let skipped: Bool
        if child.isMultiSession, let slot = slotFilter {
            completed = isChildSessionCompleted(child, slot: slot)
            skipped = isChildSessionSkipped(child, slot: slot)
        } else {
            completed = isChildCompleted(child)
            skipped = isChildFullySkipped(child)
        }

        ActivityRowView(
            activity: child,
            isCompleted: completed,
            isSkipped: skipped,
            onComplete: { onCompleteChild(child, slotFilter) },
            onSkip: { reason in onSkipChild(child, reason, slotFilter) }
        )
    }
    
    private func skipReason(for child: Activity) -> String? {
        todayLogs.first(where: { $0.activity?.id == child.id && $0.status == .skipped })?.skipReason
    }
}
