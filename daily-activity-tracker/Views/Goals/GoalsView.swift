import SwiftUI
import SwiftData

struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Goal.sortOrder) private var allGoals: [Goal]
    @Query(sort: \ActivityLog.date, order: .reverse) private var allLogs: [ActivityLog]
    @Query(sort: \Activity.sortOrder) private var allActivities: [Activity]
    @Query private var vacationDays: [VacationDay]

    private let scheduleEngine = ScheduleEngine()

    @State private var showAddGoal = false
    @State private var editingGoal: Goal?

    private var activeGoals: [Goal] {
        allGoals.filter { !$0.isArchived }
    }

    private var archivedGoals: [Goal] {
        allGoals.filter { $0.isArchived }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if activeGoals.isEmpty {
                        emptyState
                    } else {
                        ForEach(activeGoals) { goal in
                            NavigationLink(value: goal.id) {
                                GoalCardView(
                                    goal: goal,
                                    score: consistencyScore(for: goal),
                                    logs: allLogs,
                                    vacationDays: vacationDays
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !archivedGoals.isEmpty {
                        archivedSection
                    }
                }
                .padding()
            }
            .background(Color(.systemBackground))
            .navigationTitle("Goals")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddGoal = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddGoal) {
                AddGoalView()
            }
            .sheet(item: $editingGoal) { goal in
                AddGoalView(goalToEdit: goal)
            }
            .navigationDestination(for: UUID.self) { goalID in
                if let goal = allGoals.first(where: { $0.id == goalID }) {
                    GoalDetailView(goal: goal, allLogs: allLogs, vacationDays: vacationDays, allActivities: allActivities)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Goals Yet")
                .font(.title3.bold())
            Text("Set goals to track how your daily activities\ncontribute to bigger objectives.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showAddGoal = true
            } label: {
                Label("Create Goal", systemImage: "plus")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 60)
    }

    // MARK: - Archived

    private var archivedSection: some View {
        DisclosureGroup {
            ForEach(archivedGoals) { goal in
                HStack(spacing: 10) {
                    Image(systemName: goal.icon)
                        .font(.caption)
                        .foregroundStyle(Color(hex: goal.hexColor))
                    Text(goal.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .contextMenu {
                    Button {
                        goal.isArchived = false
                    } label: {
                        Label("Unarchive", systemImage: "tray.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        modelContext.delete(goal)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "archivebox")
                    .font(.caption)
                Text("Archived (\(archivedGoals.count))")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Scoring

    /// 14-day weighted completion score for contributing activities
    func consistencyScore(for goal: Goal) -> Double {
        var totalWeighted = 0.0
        var totalWeight = 0.0

        for link in goal.activityLinks {
            guard let activity = link.activity, activity.modelContext != nil else { continue }
            let w = link.weight
            let rate = scheduleEngine.completionRate(for: activity, days: 14, logs: allLogs, vacationDays: vacationDays, allActivities: allActivities)

            if rate > 0 {
                totalWeighted += rate * w
                totalWeight += w
            }
        }

        guard totalWeight > 0 else { return 0 }
        return totalWeighted / totalWeight
    }
}

// MARK: - Goal Card Component

struct GoalCardView: View {
    let goal: Goal
    let score: Double
    let logs: [ActivityLog]
    let vacationDays: [VacationDay]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: goal.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: goal.hexColor))
                    .frame(width: 32, height: 32)
                    .background(Color(hex: goal.hexColor).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Label("\(goal.activityLinks.count)", systemImage: "figure.run")
                        if !goal.metricLinks.isEmpty {
                            Label("\(goal.metricLinks.count)", systemImage: "chart.line.uptrend.xyaxis")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Consistency bar
            consistencyBar(score: score)

            // Metric summaries (compact)
            if !goal.metricLinks.isEmpty {
                metricSummaries
            }

            // Deadline
            if let deadline = goal.deadline {
                let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0
                Label(daysLeft > 0 ? "\(daysLeft)d left" : "Overdue", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(daysLeft > 0 ? Color.secondary : Color.red)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func consistencyBar(score: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("7-Day Consistency")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(score * 100))%")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(score))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(scoreColor(score).gradient)
                        .frame(width: geo.size.width * score)
                }
            }
            .frame(height: 8)
        }
    }

    /// Compact metric summaries on the card
    @ViewBuilder
    private var metricSummaries: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(goal.metricLinks.prefix(3)) { link in
                if let activity = link.activity, activity.modelContext != nil {
                    HStack(spacing: 6) {
                        Image(systemName: activity.icon)
                            .font(.system(size: 9))
                            .foregroundStyle(Color(hex: activity.hexColor))

                        Text(activity.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer()

                        // Show latest value or status
                        metricBadge(for: link, activity: activity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func metricBadge(for link: GoalActivity, activity: Activity) -> some View {
        if activity.type == .checkbox {
            // Boolean metric — show latest completion
            let completed = logs.contains {
                $0.activity?.id == activity.id && $0.status == .completed
            }
            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
                .foregroundStyle(completed ? .green : .secondary)
        } else if let progress = goal.metricProgress(for: link) {
            // Numeric with baseline/target
            Text("\(Int(progress * 100))%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor(progress))
        } else if let latest = goal.latestValue(for: link) {
            // Numeric without target
            Text(latest.cleanDisplay)
                .font(.caption2.bold())
                .foregroundStyle(Color(hex: goal.hexColor))
        } else {
            Text("—")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

}
