import SwiftUI
import SwiftData

struct GoalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var goal: Goal
    let allLogs: [ActivityLog]
    let vacationDays: [VacationDay]
    let allActivities: [Activity]

    private let scheduleEngine = ScheduleEngine()

    @State private var showEditGoal = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerCard
                if !goal.metricLinks.isEmpty { metricsSection }
                consistencySection
                activitiesBreakdown
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .navigationTitle(goal.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showEditGoal = true
                    } label: {
                        Label("Edit Goal", systemImage: "pencil")
                    }
                    Button {
                        goal.isArchived = true
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditGoal) {
            AddGoalView(goalToEdit: goal)
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: goal.icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color(hex: goal.hexColor))
                    .frame(width: 48, height: 48)
                    .background(Color(hex: goal.hexColor).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Label("\(goal.activityLinks.count) habits", systemImage: "figure.run")
                        if !goal.metricLinks.isEmpty {
                            Label("\(goal.metricLinks.count) metrics", systemImage: "chart.line.uptrend.xyaxis")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let deadline = goal.deadline {
                        let days = Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0
                        Text(days > 0 ? "\(days) days remaining" : "Deadline passed")
                            .font(.caption)
                            .foregroundStyle(days > 0 ? .orange : .red)
                    }
                }

                Spacer()
            }

            // Overall consistency score
            let score = overallScore
            VStack(spacing: 4) {
                Text("\(Int(score * 100))%")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(score))
                Text("Activity Consistency (14 days)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Metrics Section

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Metrics", icon: "chart.line.uptrend.xyaxis")

            ForEach(goal.metricLinks) { link in
                if let activity = link.activity, activity.modelContext != nil {
                    metricRow(link: link, activity: activity)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func metricRow(link: GoalActivity, activity: Activity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name + icon
            HStack(spacing: 8) {
                Image(systemName: activity.icon)
                    .font(.caption)
                    .foregroundStyle(Color(hex: activity.hexColor))
                    .frame(width: 20)
                Text(activity.name)
                    .font(.subheadline.bold())
                Spacer()

                if let dir = link.metricDirection {
                    Image(systemName: dir.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Type-specific display
            if activity.type == .metric && activity.metricKind == .photo {
                photoMetricDisplay(activity: activity)
            } else if activity.type == .checkbox || (activity.type == .metric && activity.metricKind == .checkbox) {
                booleanMetricDisplay(activity: activity)
            } else {
                numericMetricDisplay(link: link, activity: activity)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Numeric metric: progress arc + baseline/current/target
    @ViewBuilder
    private func numericMetricDisplay(link: GoalActivity, activity: Activity) -> some View {
        let sortedLogs = activity.logs
            .filter { $0.status == .completed && $0.value != nil }
            .sorted { $0.date < $1.date }
        let latestValue = sortedLogs.last?.value

        if let baseline = link.metricBaseline, let target = link.metricTarget {
            let progress = goal.metricProgress(for: link) ?? 0

            HStack(spacing: 16) {
                // Progress arc
                progressArc(progress: progress, color: Color(hex: goal.hexColor))

                VStack(alignment: .leading, spacing: 6) {
                    metricValueRow("Baseline", value: baseline, unit: activity.unit)
                    metricValueRow("Current", value: latestValue, unit: activity.unit, highlight: true)
                    metricValueRow("Target", value: target, unit: activity.unit)
                }
            }

            // AVG progress rate
            if sortedLogs.count >= 2,
               let first = sortedLogs.first, let last = sortedLogs.last {
                let daySpan = max(Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 1, 1)
                let delta = (last.value ?? 0) - baseline

                let (rate, unitLabel): (Double, String) = {
                    if daySpan < 14 {
                        return (delta / Double(daySpan), "/day")
                    } else if daySpan < 90 {
                        return (delta / (Double(daySpan) / 7.0), "/week")
                    } else {
                        return (delta / (Double(daySpan) / 30.44), "/month")
                    }
                }()

                let isPositiveDirection = (link.metricDirection?.rawValue ?? "increase") == "increase"
                let isGood = isPositiveDirection ? rate > 0 : rate < 0

                HStack(spacing: 4) {
                    Text("Avg Progress")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: rate >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isGood ? .green : .red)
                    Text("\(formatMetric(abs(rate))) \(activity.unit ?? "")\(unitLabel)")
                        .font(.caption.bold())
                        .foregroundStyle(isGood ? .green : .red)
                }
                .padding(.top, 2)
            }

            // Mini trendline
            if sortedLogs.count >= 2 {
                trendline(values: sortedLogs.map { $0.value! }, color: Color(hex: goal.hexColor))
            }
        } else if let latest = latestValue {
            // No baseline/target — just show recent values
            HStack {
                Text("Latest")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(formatMetric(latest)) \(activity.unit ?? "")")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color(hex: goal.hexColor))
            }
        } else {
            Text("No measurements yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Boolean metric: completion timeline
    @ViewBuilder
    private func booleanMetricDisplay(activity: Activity) -> some View {
        let completedDates = Set(
            activity.logs
                .filter { $0.status == .completed }
                .map { $0.date.startOfDay }
        )
        let latest = completedDates.max()
        let wasAchieved = latest != nil

        HStack {
            Image(systemName: wasAchieved ? "checkmark.circle.fill" : "circle.dotted")
                .font(.title3)
                .foregroundStyle(wasAchieved ? .green : .secondary)
            Text(wasAchieved ? "Achieved" : "Not yet")
                .font(.subheadline.bold())
                .foregroundStyle(wasAchieved ? .green : .secondary)
            Spacer()
            if let d = latest {
                Text(d, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Photo metric: thumbnail grid
    @ViewBuilder
    private func photoMetricDisplay(activity: Activity) -> some View {
        let photoLogs = activity.logs
            .filter { $0.photoFilename != nil }
            .sorted { $0.date > $1.date }
            .prefix(6)

        if photoLogs.isEmpty {
            Text("No photos logged yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(Array(photoLogs), id: \.id) { log in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: goal.hexColor).opacity(0.2))
                        .frame(height: 50)
                        .overlay {
                            if let filename = log.photoFilename,
                               let uiImage = MediaService.shared.loadPhoto(filename: filename) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 50)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                VStack(spacing: 2) {
                                    Image(systemName: "photo.fill")
                                        .font(.caption2)
                                    Text(log.date, style: .date)
                                        .font(.system(size: 8))
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                }
            }
        }
    }

    // MARK: - Consistency Section

    private var consistencySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Activity Breakdown", icon: "list.bullet")

            if goal.activityLinks.isEmpty {
                HStack {
                    Spacer()
                    Text("No contributing activities linked.\nEdit to add activities.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(.vertical, 12)
            } else {
                ForEach(goal.activityLinks.sorted(by: { ($0.activity?.name ?? "") < ($1.activity?.name ?? "") })) { link in
                    if let activity = link.activity, activity.modelContext != nil {
                        activityRow(activity: activity, weight: link.weight)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 7-Day Detail Grid

    private var activitiesBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("14-Day Detail", icon: "calendar")

            let calendar = Calendar.current
            let today = Date().startOfDay

            // Day labels
            HStack(spacing: 0) {
                Text("")
                    .frame(width: 100, alignment: .leading)
                ForEach(0..<14, id: \.self) { offset in
                    if let day = calendar.date(byAdding: .day, value: -(14 - offset), to: today) {
                        Text(dayLabel(day))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            // Per-activity rows (includes both habits and metrics)
            ForEach(goal.linkedActivities.sorted(by: { ($0.activity?.name ?? "") < ($1.activity?.name ?? "") })) { link in
                if let activity = link.activity, activity.modelContext != nil {
                    HStack(spacing: 0) {
                        HStack(spacing: 4) {
                            if link.role == .metric {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 7))
                                    .foregroundStyle(Color(hex: goal.hexColor))
                            }
                            Text(activity.name)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .frame(width: 100, alignment: .leading)

                        ForEach(0..<14, id: \.self) { offset in
                            if let day = calendar.date(byAdding: .day, value: -(14 - offset), to: today) {
                                dayCell(activity: activity, date: day)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Sub-components

    private func activityRow(activity: Activity, weight: Double) -> some View {
        let rate = scheduleEngine.completionRate(for: activity, days: 14, logs: allLogs, vacationDays: vacationDays, allActivities: allActivities)
        return HStack(spacing: 10) {
            Image(systemName: activity.icon)
                .font(.caption)
                .foregroundStyle(Color(hex: activity.hexColor))
                .frame(width: 24)

            Text(activity.name)
                .font(.subheadline)

            Spacer()

            if weight != 1.0 {
                Text("×\(String(format: "%.1f", weight))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }

            Text("\(Int(rate * 100))%")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor(rate))
                .frame(width: 36, alignment: .trailing)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(scoreColor(rate))
                        .frame(width: geo.size.width * rate)
                }
            }
            .frame(width: 50, height: 6)
        }
    }

    private func dayCell(activity: Activity, date: Date) -> some View {
        let vacationSet = Set(vacationDays.map { $0.date.startOfDay })
        let isVacation = vacationSet.contains(date.startOfDay)
        let beforeCreated = date.startOfDay < activity.createdDate.startOfDay
        let afterStopped = activity.stoppedAt.map { date.startOfDay > $0 } ?? false

        // Container: check if all children completed on that day
        let completed: Bool
        let isSkipped: Bool
        if activity.type == .container {
            let children = activity.historicalChildren(on: date, from: allActivities)
            completed = !children.isEmpty && children.allSatisfy { child in
                allLogs.contains {
                    $0.activity?.id == child.id &&
                    $0.status == .completed &&
                    $0.date.isSameDay(as: date)
                }
            }
            // All children skipped on this day
            isSkipped = !children.isEmpty && !completed && children.allSatisfy { child in
                allLogs.contains {
                    $0.activity?.id == child.id &&
                    $0.status == .skipped &&
                    $0.date.isSameDay(as: date)
                }
            }
        } else {
            completed = allLogs.contains {
                $0.activity?.id == activity.id &&
                $0.status == .completed &&
                $0.date.isSameDay(as: date)
            }
            isSkipped = allLogs.contains {
                $0.activity?.id == activity.id &&
                $0.status == .skipped &&
                $0.date.isSameDay(as: date)
            }
        }

        let color: Color
        if isVacation {
            color = .blue.opacity(0.3)
        } else if beforeCreated || afterStopped {
            color = .clear
        } else if completed {
            color = .green
        } else if isSkipped {
            color = .orange.opacity(0.4)
        } else {
            let schedule = activity.scheduleActive(on: date)
            color = schedule.isScheduled(on: date) ? Color(.systemGray5) : .clear
        }

        return RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: 14, height: 14)
    }

    private func progressArc(progress: Double, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: progress)
            Text("\(Int(progress * 100))%")
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .frame(width: 64, height: 64)
    }

    private func trendline(values: [Double], color: Color) -> some View {
        let minVal = values.min() ?? 0
        let maxVal = values.max() ?? 1
        let range = max(maxVal - minVal, 0.001)

        return GeometryReader { geo in
            Path { path in
                for (i, v) in values.enumerated() {
                    let x = geo.size.width * (Double(i) / max(Double(values.count - 1), 1))
                    let y = geo.size.height * (1 - (v - minVal) / range)
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, lineWidth: 2)
        }
        .frame(height: 40)
    }

    private func metricValueRow(_ label: String, value: Double?, unit: String?, highlight: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            if let v = value {
                Text("\(formatMetric(v)) \(unit ?? "")")
                    .font(.caption.bold())
                    .foregroundStyle(highlight ? Color(hex: goal.hexColor) : .primary)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var overallScore: Double {
        var totalWeighted = 0.0
        var totalWeight = 0.0

        for link in goal.activityLinks {
            guard let activity = link.activity, activity.modelContext != nil else { continue }
            let w = link.weight
            let rate = scheduleEngine.completionRate(for: activity, days: 14, logs: allLogs, vacationDays: vacationDays, allActivities: allActivities)

            if rate >= 0 {
                totalWeighted += rate * w
                totalWeight += w
            }
        }

        guard totalWeight > 0 else { return 0 }
        return totalWeighted / totalWeight
    }


    private func formatMetric(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return String(formatter.string(from: date).prefix(2))
    }
}
