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
        allGoals.filter { !$0.isPaused }
    }

    private var pausedGoals: [Goal] {
        allGoals.filter { $0.isPaused }
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

                    if !pausedGoals.isEmpty {
                        pausedSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
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
                    .background(
                        LinearGradient(
                            colors: [WDS.strengthAccent, WDS.cardioAccent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: WDS.strengthAccent.opacity(0.3), radius: 8, y: 4)
            }
        }
        .padding(.top, 60)
    }

    // MARK: - Paused

    private var pausedSection: some View {
        DisclosureGroup {
            ForEach(pausedGoals) { goal in
                NavigationLink(value: goal.id) {
                    GoalCardView(
                        goal: goal,
                        score: 0,
                        logs: allLogs,
                        vacationDays: vacationDays
                    )
                    .grayscale(1)
                    .opacity(0.7)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if goal.isManuallyPaused {
                        Button {
                            goal.isManuallyPaused = false
                        } label: {
                            Label("Unpause", systemImage: "play.circle")
                        }
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
                Image(systemName: "pause.circle")
                    .font(.caption)
                Text("Paused (\(pausedGoals.count))")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Scoring

    /// 14-day weighted completion score for contributing activities
    func consistencyScore(for goal: Goal) -> Double {
        goal.consistencyScore(days: 14, logs: allLogs, vacationDays: vacationDays, allActivities: allActivities, scheduleEngine: scheduleEngine)
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
                    .foregroundStyle(goal.isPaused ? .secondary : Color(hex: goal.hexColor))
                    .frame(width: 32, height: 32)
                    .background((goal.isPaused ? Color.gray : Color(hex: goal.hexColor)).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(goal.title)
                            .font(.headline)
                            .foregroundStyle(goal.isPaused ? .secondary : .primary)
                        if goal.isPaused {
                            Text("PAUSED")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
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

            // Consistency bar — skip for on-hold goals
            if goal.isPaused {
                HStack {
                    Text("7-Day Consistency")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("—")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } else {
                consistencyBar(score: score)
            }

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
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: WDS.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
        .opacity(goal.isPaused ? 0.7 : 1.0)
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
                            .foregroundStyle(activity.isStopped ? .secondary : Color(hex: activity.hexColor))

                        Text(activity.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if activity.isStopped {
                            Text("Paused")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.orange)
                        }

                        Spacer()

                        // Show latest value or status
                        if activity.isStopped {
                            Text("—")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            metricBadge(for: link, activity: activity)
                        }
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
