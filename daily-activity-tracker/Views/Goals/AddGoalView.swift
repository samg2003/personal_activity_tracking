import SwiftUI
import SwiftData

struct AddGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Activity.sortOrder) private var allActivities: [Activity]

    var goalToEdit: Goal?

    @State private var title = ""
    @State private var icon = "target"
    @State private var hexColor = "#FF3B30"
    @State private var deadline: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date())!
    @State private var hasDeadline = false

    // Activity linking with roles
    @State private var linkedItems: [LinkedItem] = []

    private let colorOptions = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759",
        "#00C7BE", "#007AFF", "#5856D6", "#AF52DE",
        "#FF2D55", "#A2845E", "#8E8E93", "#FF6B35",
    ]

    private let iconOptions = [
        "target", "flame.fill", "heart.fill", "figure.run",
        "brain", "drop.fill", "leaf.fill", "dumbbell.fill",
        "fork.knife", "moon.fill", "sun.max.fill", "bolt.fill",
        "star.fill", "trophy.fill", "chart.line.uptrend.xyaxis", "pills.fill",
    ]

    /// Only standalone, containers, and metrics are linkable — excludes sub-activities and reminders
    private var linkableActivities: [Activity] {
        allActivities.filter {
            $0.parent == nil
            && $0.schedule.type != .sticky && $0.schedule.type != .adhoc
        }
    }

    private var metricCount: Int {
        linkedItems.filter { $0.role == .metric }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                basicSection
                activitiesSection
                linkedItemsSection
            }
            .navigationTitle(goalToEdit == nil ? "New Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { loadGoalIfEditing() }
        }
    }

    // MARK: - Sections

    private var basicSection: some View {
        Section("Goal") {
            TextField("Title (e.g., \"Get Fit\")", text: $title)

            // Icon picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                    ForEach(iconOptions, id: \.self) { ic in
                        Button {
                            icon = ic
                        } label: {
                            Image(systemName: ic)
                                .font(.system(size: 16))
                                .frame(width: 32, height: 32)
                                .background(icon == ic ? Color(hex: hexColor).opacity(0.2) : Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(icon == ic ? Color(hex: hexColor) : .clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Color picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                    ForEach(colorOptions, id: \.self) { color in
                        Button {
                            hexColor = color
                        } label: {
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(.white, lineWidth: hexColor == color ? 3 : 0)
                                )
                                .shadow(color: hexColor == color ? Color(hex: color).opacity(0.5) : .clear, radius: 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Deadline
            Toggle("Set Deadline", isOn: $hasDeadline)
            if hasDeadline {
                DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
            }
        }
    }

    private var activitiesSection: some View {
        Section("Add Activities") {
            if linkableActivities.isEmpty {
                Text("No activities available. Create activities first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let linkedIDs = Set(linkedItems.map { $0.activityID })
                // Filter out children whose parent container is already linked (prevents double-counting)
                let unlinked = linkableActivities.filter { activity in
                    guard !linkedIDs.contains(activity.id) else { return false }
                    if let parent = activity.parent, linkedIDs.contains(parent.id) { return false }
                    return true
                }

                if unlinked.isEmpty {
                    Text("All activities are linked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(unlinked) { activity in
                        Button {
                            addLinkedItem(activity)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Color(hex: hexColor))

                                Image(systemName: activity.icon)
                                    .font(.caption)
                                    .foregroundStyle(Color(hex: activity.hexColor))
                                    .frame(width: 20)

                                Text(activity.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)

                                Spacer()

                                if activity.isStopped {
                                    Text("Paused")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var linkedItemsSection: some View {
        if !linkedItems.isEmpty {
            Section("Linked (\(linkedItems.count))") {
                ForEach($linkedItems) { $item in
                    linkedItemRow(item: $item)
                }
                .onDelete { indexSet in
                    linkedItems.remove(atOffsets: indexSet)
                }
            }
        }
    }

    @ViewBuilder
    private func linkedItemRow(item: Binding<LinkedItem>) -> some View {
        let activity = linkableActivities.first { $0.id == item.wrappedValue.activityID }

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let activity {
                    Image(systemName: activity.icon)
                        .font(.caption)
                        .foregroundStyle(activity.isStopped ? .secondary : Color(hex: activity.hexColor))
                        .frame(width: 20)
                    Text(activity.name)
                        .font(.subheadline)
                        .foregroundStyle(activity.isStopped ? .secondary : .primary)
                    if activity.isStopped {
                        Text("Paused")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Spacer()

                // Role toggle (containers are always "Habit" role)
                if activity?.type == .container {
                    Text("Habit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("", selection: item.role) {
                        Text("Habit").tag(GoalActivityRole.activity)
                        Text("Metric").tag(GoalActivityRole.metric)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .onChange(of: item.wrappedValue.role) { _, newRole in
                        if newRole == .metric && metricCount > 5 {
                            item.wrappedValue.role = .activity
                        }
                    }
                }
            }

            // Metric config (only for metric-role numeric activities)
            if item.wrappedValue.role == .metric,
               let act = activity, act.type == .value || act.type == .cumulative {
                metricConfig(item: item, activity: act)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func metricConfig(item: Binding<LinkedItem>, activity: Activity) -> some View {
        VStack(spacing: 8) {
            Picker("Direction", selection: item.direction) {
                ForEach(MetricDirection.allCases, id: \.self) { dir in
                    Label(dir.label, systemImage: dir.icon).tag(dir)
                }
            }
            .font(.caption)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Baseline")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("Start", text: item.baselineText)
                        .keyboardType(.decimalPad)
                        .font(.caption)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("Goal", text: item.targetText)
                        .keyboardType(.decimalPad)
                        .font(.caption)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func addLinkedItem(_ activity: Activity) {
        linkedItems.append(LinkedItem(activityID: activity.id, role: .activity))
    }

    private func save() {
        let goal = goalToEdit ?? Goal(title: title)

        goal.title = title
        goal.icon = icon
        goal.hexColor = hexColor
        goal.deadline = hasDeadline ? deadline : nil

        if goalToEdit == nil {
            modelContext.insert(goal)
        }

        // Sync linked activities
        let existingLinks = goal.linkedActivities
        let newIDs = Set(linkedItems.map { $0.activityID })

        // Remove unlinked
        for link in existingLinks {
            if let actID = link.activity?.id, !newIDs.contains(actID) {
                modelContext.delete(link)
            }
        }

        // Add/update links
        for item in linkedItems {
            if let existingLink = existingLinks.first(where: { $0.activity?.id == item.activityID }) {
                // Update existing
                existingLink.role = item.role
                if item.role == .metric {
                    existingLink.metricBaseline = Double(item.baselineText)
                    existingLink.metricTarget = Double(item.targetText)
                    existingLink.metricDirection = item.direction
                } else {
                    existingLink.metricBaseline = nil
                    existingLink.metricTarget = nil
                    existingLink.metricDirectionRaw = nil
                }
            } else if let activity = allActivities.first(where: { $0.id == item.activityID }) {
                let link = GoalActivity(goal: goal, activity: activity, role: item.role)
                if item.role == .metric {
                    link.metricBaseline = Double(item.baselineText)
                    link.metricTarget = Double(item.targetText)
                    link.metricDirection = item.direction
                }
                modelContext.insert(link)
            }
        }

        dismiss()
    }

    private func loadGoalIfEditing() {
        guard let goal = goalToEdit else { return }
        title = goal.title
        icon = goal.icon
        hexColor = goal.hexColor
        hasDeadline = goal.deadline != nil
        deadline = goal.deadline ?? Calendar.current.date(byAdding: .month, value: 3, to: Date())!

        linkedItems = goal.linkedActivities.compactMap { link in
            guard let actID = link.activity?.id else { return nil }
            var item = LinkedItem(activityID: actID, role: link.role)
            if link.role == .metric {
                item.direction = link.metricDirection ?? .decrease
                item.baselineText = link.metricBaseline.map { String($0) } ?? ""
                item.targetText = link.metricTarget.map { String($0) } ?? ""
            }
            return item
        }
    }
}

// MARK: - LinkedItem (Form State)

struct LinkedItem: Identifiable {
    let id = UUID()
    var activityID: UUID
    var role: GoalActivityRole
    var direction: MetricDirection = .decrease
    var baselineText: String = ""
    var targetText: String = ""
}
