import Foundation
import SwiftData

// MARK: - Supporting Enums

enum GoalActivityRole: String, Codable, CaseIterable {
    case activity  // Contributing habit (e.g., "Strength Training")
    case metric    // Outcome measurement (e.g., "Measure Body Fat")
}

enum MetricDirection: String, Codable, CaseIterable {
    case increase  // Higher is better (deadhang time, steps)
    case decrease  // Lower is better (body fat %, weight)

    var label: String {
        switch self {
        case .increase: return "Higher is better"
        case .decrease: return "Lower is better"
        }
    }

    var icon: String {
        switch self {
        case .increase: return "arrow.up.right"
        case .decrease: return "arrow.down.right"
        }
    }
}

// MARK: - Goal

@Model
final class Goal {
    var id: UUID = UUID()
    var title: String = ""
    var icon: String = "target"
    var hexColor: String = "#FF3B30"
    var deadline: Date?
    var isArchived: Bool = false
    var createdAt: Date?
    var sortOrder: Int = 0

    /// Safe accessor for createdAt
    var createdDate: Date { createdAt ?? Date.distantPast }

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \GoalActivity.goal)
    var linkedActivities: [GoalActivity] = []

    // MARK: - Computed

    /// Contributing habit links
    var activityLinks: [GoalActivity] {
        linkedActivities.filter { $0.role == .activity }
    }

    /// Outcome metric links (max 5)
    var metricLinks: [GoalActivity] {
        linkedActivities.filter { $0.role == .metric }
    }

    /// All contributing activities
    var activities: [Activity] {
        activityLinks
            .compactMap { $0.activity }
            .filter { $0.modelContext != nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// All metric activities
    var metrics: [Activity] {
        metricLinks
            .compactMap { $0.activity }
            .filter { $0.modelContext != nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Progress for a specific metric link (0.0 to 1.0, nil if not calculable)
    func metricProgress(for link: GoalActivity) -> Double? {
        guard link.role == .metric,
              let activity = link.activity,
              activity.modelContext != nil,
              let baseline = link.metricBaseline,
              let target = link.metricTarget,
              abs(target - baseline) > 0.001
        else { return nil }

        // Latest value from the activity's logs
        guard let latestLog = activity.logs
            .filter({ $0.status == .completed && $0.value != nil })
            .sorted(by: { $0.date > $1.date })
            .first,
              let current = latestLog.value
        else { return nil }

        let progress = (current - baseline) / (target - baseline)
        return min(max(progress, 0), 1.0)
    }

    /// Latest measurement value for a metric link
    func latestValue(for link: GoalActivity) -> Double? {
        guard let activity = link.activity, activity.modelContext != nil else { return nil }
        return activity.logs
            .filter { $0.status == .completed && $0.value != nil }
            .sorted { $0.date > $1.date }
            .first?.value
    }

    /// Weighted-average completion rate across contributing activities
    func consistencyScore(
        days: Int,
        logs: [ActivityLog],
        vacationDays: [VacationDay],
        allActivities: [Activity],
        scheduleEngine: ScheduleEngineProtocol
    ) -> Double {
        var totalWeighted = 0.0
        var totalWeight = 0.0

        for link in activityLinks {
            guard let activity = link.activity, activity.modelContext != nil else { continue }
            let w = link.weight
            let rate = scheduleEngine.completionRate(for: activity, days: days, logs: logs, vacationDays: vacationDays, allActivities: allActivities)
            if rate > 0 {
                totalWeighted += rate * w
                totalWeight += w
            }
        }

        guard totalWeight > 0 else { return 0 }
        return totalWeighted / totalWeight
    }

    // MARK: - Init

    init(
        title: String,
        icon: String = "target",
        hexColor: String = "#FF3B30",
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.icon = icon
        self.hexColor = hexColor
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}

// MARK: - GoalActivity (Junction with Role)

@Model
final class GoalActivity {
    var id: UUID = UUID()
    var roleRaw: String = GoalActivityRole.activity.rawValue
    var weight: Double = 1.0

    // Metric-specific fields (only when role == .metric)
    var metricBaseline: Double?
    var metricTarget: Double?
    var metricDirectionRaw: String?

    var goal: Goal?
    var activity: Activity?

    // MARK: - Computed

    var role: GoalActivityRole {
        get { GoalActivityRole(rawValue: roleRaw) ?? .activity }
        set { roleRaw = newValue.rawValue }
    }

    var metricDirection: MetricDirection? {
        get { metricDirectionRaw.flatMap { MetricDirection(rawValue: $0) } }
        set { metricDirectionRaw = newValue?.rawValue }
    }

    // MARK: - Init

    init(
        goal: Goal? = nil,
        activity: Activity? = nil,
        role: GoalActivityRole = .activity,
        weight: Double = 1.0
    ) {
        self.id = UUID()
        self.goal = goal
        self.activity = activity
        self.roleRaw = role.rawValue
        self.weight = weight
    }
}
