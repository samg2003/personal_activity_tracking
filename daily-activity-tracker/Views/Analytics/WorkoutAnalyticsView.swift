import SwiftUI
import SwiftData
import Charts

/// Workout-specific analytics: strength (1RM trends, volume, PRs) and cardio (pace, distance).
struct WorkoutAnalyticsView: View {
    @Query(sort: \StrengthSession.date, order: .reverse) private var strengthSessions: [StrengthSession]
    @Query(sort: \CardioSession.date, order: .reverse) private var cardioSessions: [CardioSession]
    @Query private var muscleGroups: [MuscleGroup]
    @Query private var exercises: [Exercise]

    private let calendar = Calendar.current

    // MARK: - Derived Data

    private var completedStrengthSessions: [StrengthSession] {
        strengthSessions.filter { $0.status == .completed }
    }

    private var completedCardioSessions: [CardioSession] {
        cardioSessions.filter { $0.status == .completed }
    }

    private var allSetLogs: [WorkoutSetLog] {
        completedStrengthSessions.flatMap(\.setLogs)
    }

    private var allCardioLogs: [CardioSessionLog] {
        completedCardioSessions.flatMap(\.logs)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            if completedStrengthSessions.isEmpty && completedCardioSessions.isEmpty {
                emptyState
            } else {
                VStack(spacing: 24) {
                    summaryCards
                    strengthSection
                    cardioSection
                }
                .padding()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis.ascending")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Workouts Yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Complete a strength or cardio session to see analytics here.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        let thisWeekStart = calendar.date(byAdding: .day, value: -6, to: Date().startOfDay)!
        let lastWeekStart = calendar.date(byAdding: .day, value: -13, to: Date().startOfDay)!
        let lastWeekEnd = calendar.date(byAdding: .day, value: -7, to: Date().startOfDay)!

        let thisWeekStrength = completedStrengthSessions.filter { $0.date >= thisWeekStart }
        let lastWeekStrength = completedStrengthSessions.filter { $0.date >= lastWeekStart && $0.date < lastWeekEnd }

        let thisWeekCardio = completedCardioSessions.filter { $0.date >= thisWeekStart }
        let lastWeekCardio = completedCardioSessions.filter { $0.date >= lastWeekStart && $0.date < lastWeekEnd }

        let totalSessions = thisWeekStrength.count + thisWeekCardio.count
        let lastTotalSessions = lastWeekStrength.count + lastWeekCardio.count

        let thisWeekVolume = thisWeekStrength.flatMap(\.setLogs).filter { !$0.isWarmup }
            .reduce(0.0) { $0 + $1.weight * Double($1.reps) }
        let lastWeekVolume = lastWeekStrength.flatMap(\.setLogs).filter { !$0.isWarmup }
            .reduce(0.0) { $0 + $1.weight * Double($1.reps) }

        let thisWeekDistance = thisWeekCardio.flatMap(\.logs).compactMap(\.distance).reduce(0, +) / 1000.0
        let lastWeekDistance = lastWeekCardio.flatMap(\.logs).compactMap(\.distance).reduce(0, +) / 1000.0

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                summaryCard(
                    title: "Sessions",
                    value: "\(totalSessions)",
                    delta: totalSessions - lastTotalSessions,
                    icon: "figure.strengthtraining.traditional",
                    color: .blue
                )
                if thisWeekVolume > 0 || lastWeekVolume > 0 {
                    summaryCard(
                        title: "Volume",
                        value: formatVolume(thisWeekVolume),
                        delta: Int(thisWeekVolume - lastWeekVolume),
                        icon: "scalemass.fill",
                        color: .purple
                    )
                }
                if thisWeekDistance > 0 || lastWeekDistance > 0 {
                    summaryCard(
                        title: "Distance",
                        value: String(format: "%.1f km", thisWeekDistance),
                        delta: Int((thisWeekDistance - lastWeekDistance) * 10),
                        icon: "figure.run",
                        color: .green
                    )
                }
            }
        }
    }

    private func summaryCard(title: String, value: String, delta: Int, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            if delta != 0 {
                HStack(spacing: 2) {
                    Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                    Text("vs last wk")
                        .font(.system(size: 9))
                }
                .foregroundStyle(delta > 0 ? .green : .red)
            } else {
                Text("same as last wk")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 130, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Strength Section

    @ViewBuilder
    private var strengthSection: some View {
        if !completedStrengthSessions.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Strength", icon: "dumbbell.fill")
                estimatedOneRMSection
                volumeByMuscleSection
                personalRecordsSection
            }
        }
    }

    // MARK: 1RM Trends (line chart per exercise, last 8 weeks)

    private var estimatedOneRMSection: some View {
        let exerciseSets = Dictionary(grouping: allSetLogs.filter { !$0.isWarmup && $0.exercise != nil }) {
            $0.exercise!.id
        }

        // Sort by recency, pick top 5
        let sorted = exerciseSets.sorted { a, b in
            let aMax = a.value.map(\.completedAt).max() ?? .distantPast
            let bMax = b.value.map(\.completedAt).max() ?? .distantPast
            return aMax > bMax
        }.prefix(5)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Estimated 1RM Trends")
                .font(.subheadline.weight(.semibold))

            ForEach(Array(sorted), id: \.key) { exerciseID, sets in
                let exerciseName = sets.first?.exercise?.name ?? "Unknown"
                let weeklyData = weeklyMax1RM(sets: sets, weeks: 8)

                if !weeklyData.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exerciseName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        Chart(weeklyData, id: \.weekStart) { point in
                            LineMark(
                                x: .value("Week", point.weekStart),
                                y: .value("1RM", point.value)
                            )
                            .foregroundStyle(Color.blue.gradient)
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Week", point.weekStart),
                                y: .value("1RM", point.value)
                            )
                            .foregroundStyle(.blue)
                            .symbolSize(20)
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text("\(Int(v))")
                                            .font(.system(size: 9))
                                    }
                                }
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                                AxisValueLabel {
                                    if let d = value.as(Date.self) {
                                        Text(d, format: .dateTime.month(.abbreviated).day())
                                            .font(.system(size: 9))
                                    }
                                }
                            }
                        }
                        .frame(height: 100)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: Volume by Muscle Group

    private var volumeByMuscleSection: some View {
        let thisWeekStart = calendar.date(byAdding: .day, value: -6, to: Date().startOfDay)!
        let thisWeekSets = allSetLogs.filter { !$0.isWarmup && $0.completedAt >= thisWeekStart }

        // Group sets by muscle group via exercise's muscle involvements
        var muscleSetCounts: [UUID: Int] = [:]
        for set in thisWeekSets {
            guard let exercise = set.exercise else { continue }
            for involvement in exercise.muscleInvolvements {
                guard let mgID = involvement.muscleGroupID else { continue }
                muscleSetCounts[mgID, default: 0] += 1
            }
        }

        let parentGroups = muscleGroups.filter { $0.isParent }
        let bars: [(name: String, sets: Int)] = parentGroups
            .map { mg in
                // Also count sub-group sets
                let childIDs = muscleGroups.filter { $0.parentID == mg.id }.map(\.id)
                let total = ([mg.id] + childIDs).reduce(0) { $0 + (muscleSetCounts[$1] ?? 0) }
                return (mg.name, total)
            }
            .filter { $0.sets > 0 }
            .sorted { $0.sets > $1.sets }

        return VStack(alignment: .leading, spacing: 8) {
            Text("Volume by Muscle (This Week)")
                .font(.subheadline.weight(.semibold))

            if bars.isEmpty {
                Text("No sets logged this week")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                Chart(bars, id: \.name) { item in
                    BarMark(
                        x: .value("Sets", item.sets),
                        y: .value("Muscle", item.name)
                    )
                    .foregroundStyle(Color.purple.gradient)
                    .annotation(position: .trailing) {
                        Text("\(item.sets)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(String.self) {
                                Text(v)
                                    .font(.system(size: 11))
                            }
                        }
                    }
                }
                .frame(height: CGFloat(max(bars.count * 32, 60)))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Personal Records

    private var personalRecordsSection: some View {
        let exerciseSets = Dictionary(grouping: allSetLogs.filter { !$0.isWarmup && $0.exercise != nil }) {
            $0.exercise!.id
        }

        // Best 1RM per exercise
        let prs: [(name: String, oneRM: Double, weight: Double, reps: Int)] = Array(exerciseSets.compactMap { _, sets in
            guard let best = sets.compactMap({ s -> (set: WorkoutSetLog, rm: Double)? in
                guard let rm = s.estimated1RM else { return nil }
                return (s, rm)
            }).max(by: { $0.rm < $1.rm }) else { return nil }

            return (best.set.exercise?.name ?? "", best.rm, best.set.weight, best.set.reps)
        }
        .sorted { $0.oneRM > $1.oneRM }
        .prefix(5))

        return VStack(alignment: .leading, spacing: 8) {
            Text("Personal Records")
                .font(.subheadline.weight(.semibold))

            if prs.isEmpty {
                Text("Log some sets to see PRs")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(prs), id: \.name) { pr in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pr.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text("\(Int(pr.weight))kg × \(pr.reps)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(pr.oneRM))")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .foregroundStyle(.blue)
                            Text("est. 1RM")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Cardio Section

    @ViewBuilder
    private var cardioSection: some View {
        if !completedCardioSessions.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Cardio", icon: "figure.run")
                weeklyDistanceSection
                paceTrendsSection
            }
        }
    }

    // MARK: Weekly Distance (bar chart, last 8 weeks)

    private var weeklyDistanceSection: some View {
        let weeks = 8
        let today = Date().startOfDay

        let bars: [(label: String, distance: Double, weekStart: Date)] = (0..<weeks).reversed().map { offset in
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: -offset, to: today)!
            let weekStart = calendar.date(byAdding: .day, value: -6, to: weekEnd)!
            let fmt = DateFormatter()
            fmt.dateFormat = "M/d"

            let distance = allCardioLogs.filter { log in
                guard let session = log.session, session.status == .completed else { return false }
                return session.date >= weekStart && session.date <= weekEnd
            }
            .compactMap(\.distance)
            .reduce(0, +) / 1000.0

            return (fmt.string(from: weekStart), distance, weekStart)
        }

        return VStack(alignment: .leading, spacing: 8) {
            Text("Weekly Distance")
                .font(.subheadline.weight(.semibold))

            Chart(bars, id: \.weekStart) { item in
                BarMark(
                    x: .value("Week", item.label),
                    y: .value("km", item.distance)
                )
                .foregroundStyle(Color.green.gradient)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: "%.0f", v))
                                .font(.system(size: 9))
                        }
                    }
                }
            }
            .frame(height: 120)

            // Stats
            let totalDist = bars.map(\.distance).reduce(0, +)
            let avgDist = totalDist / Double(max(bars.filter { $0.distance > 0 }.count, 1))
            HStack {
                statLabel("Avg/wk", value: String(format: "%.1f km", avgDist))
                Divider().frame(height: 20)
                statLabel("Total", value: String(format: "%.1f km", totalDist))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Pace Trends

    private var paceTrendsSection: some View {
        let logsWithPace = allCardioLogs.filter { $0.avgPace != nil && $0.avgPace! > 0 }

        let weeklyPace = weeklyAveragePace(logs: logsWithPace, weeks: 8)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Average Pace Trend")
                .font(.subheadline.weight(.semibold))

            if weeklyPace.isEmpty {
                Text("No pace data yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                Chart(weeklyPace, id: \.weekStart) { point in
                    LineMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Pace", point.value)
                    )
                    .foregroundStyle(Color.orange.gradient)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Pace", point.value)
                    )
                    .foregroundStyle(.orange)
                    .symbolSize(20)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(formatPace(v))
                                    .font(.system(size: 9))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel {
                            if let d = value.as(Date.self) {
                                Text(d, format: .dateTime.month(.abbreviated).day())
                                    .font(.system(size: 9))
                            }
                        }
                    }
                }
                .frame(height: 120)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title.uppercased())
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func statLabel(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatVolume(_ vol: Double) -> String {
        if vol >= 1000 {
            return String(format: "%.0fk kg", vol / 1000)
        }
        return String(format: "%.0f kg", vol)
    }

    private func formatPace(_ secsPerKm: Double) -> String {
        let min = Int(secsPerKm) / 60
        let sec = Int(secsPerKm) % 60
        return "\(min):\(String(format: "%02d", sec))"
    }

    // MARK: - Data Aggregation

    struct WeeklyDataPoint {
        let weekStart: Date
        let value: Double
    }

    /// Returns the max estimated 1RM per week for a set of WorkoutSetLogs.
    private func weeklyMax1RM(sets: [WorkoutSetLog], weeks: Int) -> [WeeklyDataPoint] {
        let today = Date().startOfDay
        return (0..<weeks).reversed().compactMap { offset in
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: -offset, to: today)!
            let weekStart = calendar.date(byAdding: .day, value: -6, to: weekEnd)!

            let weekSets = sets.filter { $0.completedAt >= weekStart && $0.completedAt <= weekEnd }
            guard let max1RM = weekSets.compactMap(\.estimated1RM).max() else { return nil }

            return WeeklyDataPoint(weekStart: weekStart, value: max1RM)
        }
    }

    /// Returns the average pace per week for cardio logs.
    private func weeklyAveragePace(logs: [CardioSessionLog], weeks: Int) -> [WeeklyDataPoint] {
        let today = Date().startOfDay
        return (0..<weeks).reversed().compactMap { offset in
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: -offset, to: today)!
            let weekStart = calendar.date(byAdding: .day, value: -6, to: weekEnd)!

            let weekLogs = logs.filter { log in
                guard let session = log.session else { return false }
                return session.date >= weekStart && session.date <= weekEnd
            }
            let paces = weekLogs.compactMap(\.avgPace).filter { $0 > 0 }
            guard !paces.isEmpty else { return nil }

            let avg = paces.reduce(0, +) / Double(paces.count)
            return WeeklyDataPoint(weekStart: weekStart, value: avg)
        }
    }
}
