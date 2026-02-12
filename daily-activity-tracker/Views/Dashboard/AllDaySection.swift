import SwiftUI

/// Always-visible section for cumulative (All Day) activities at the top of the dashboard
struct AllDaySection: View {
    let activities: [Activity]
    let cumulativeValues: (Activity) -> Double
    let onAdd: (Activity, Double) -> Void

    var body: some View {
        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "arrow.2.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("ALL DAY")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(activities) { activity in
                            CumulativeRingView(
                                activity: activity,
                                currentValue: cumulativeValues(activity),
                                onAdd: { value in onAdd(activity, value) }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}
