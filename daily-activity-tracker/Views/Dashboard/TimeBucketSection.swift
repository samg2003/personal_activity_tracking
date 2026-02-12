import SwiftUI

struct TimeBucketSection: View {
    let slot: TimeSlot
    let activities: [Activity]
    let isAutoCollapsed: Bool
    let isCompleted: (Activity) -> Bool
    let isSkipped: (Activity) -> Bool
    let onComplete: (Activity) -> Void
    let onSkip: (Activity, String) -> Void

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: slot.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(slot.displayName.uppercased())
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Count
                    let doneCount = activities.filter { isCompleted($0) }.count
                    Text("\(doneCount)/\(activities.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(activities) { activity in
                    ActivityRowView(
                        activity: activity,
                        isCompleted: isCompleted(activity),
                        isSkipped: isSkipped(activity),
                        onComplete: { onComplete(activity) },
                        onSkip: { reason in onSkip(activity, reason) }
                    )
                }
            }
        }
        .onAppear {
            // Auto-collapse future windows
            isExpanded = !isAutoCollapsed
        }
    }
}
