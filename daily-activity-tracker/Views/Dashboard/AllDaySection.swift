import SwiftUI

/// Always-visible section for cumulative (All Day) activities at the top of the dashboard
struct AllDaySection: View {
    let activities: [Activity]
    let cumulativeValues: (Activity) -> Double
    let onAdd: (Activity, Double) -> Void
    var quickIncrements: ((Activity) -> Double)?
    var isSkipped: ((Activity) -> Bool)?
    var onSkip: ((Activity, String) -> Void)?
    var onShowLogs: ((Activity) -> Void)?

    var body: some View {
        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.2.circlepath")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WDS.infoAccent)
                        .frame(width: 22, height: 22)
                        .background(WDS.infoAccent.opacity(0.12))
                        .clipShape(Circle())

                    Text("ALL DAY")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(WDS.infoAccent)

                    Spacer()

                    Text("\(activities.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(WDS.infoAccent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(WDS.infoAccent.opacity(0.1))
                        .clipShape(Capsule())
                }

                ForEach(activities) { activity in
                    CumulativeRingView(
                        activity: activity,
                        currentValue: cumulativeValues(activity),
                        onAdd: { value in onAdd(activity, value) },
                        quickIncrement: quickIncrements?(activity) ?? 1,
                        isSkipped: isSkipped?(activity) ?? false,
                        onSkip: onSkip.map { closure in { reason in closure(activity, reason) } },
                        onShowLogs: onShowLogs.map { closure in { closure(activity) } }
                    )
                }
            }
        }
    }
}

