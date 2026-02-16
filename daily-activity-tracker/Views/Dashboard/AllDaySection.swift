import SwiftUI

/// Always-visible section for cumulative (All Day) activities at the top of the dashboard
struct AllDaySection: View {
    let activities: [Activity]
    let cumulativeValues: (Activity) -> Double
    let onAdd: (Activity, Double) -> Void
    var isSkipped: ((Activity) -> Bool)?
    var onSkip: ((Activity, String) -> Void)?
    var onShowLogs: ((Activity) -> Void)?

    var body: some View {
        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.2.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("ALL DAY")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                ForEach(activities) { activity in
                    CumulativeRingView(
                        activity: activity,
                        currentValue: cumulativeValues(activity),
                        onAdd: { value in onAdd(activity, value) },
                        isSkipped: isSkipped?(activity) ?? false,
                        onSkip: onSkip.map { closure in { reason in closure(activity, reason) } },
                        onShowLogs: onShowLogs.map { closure in { closure(activity) } }
                    )
                }
            }
        }
    }
}

