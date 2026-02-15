import SwiftUI
import SwiftData

/// Detail view for an activity: shows photo timeline, camera button, and recent logs
struct ActivityDetailView: View {
    let activity: Activity
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ActivityLog.date, order: .reverse) private var allLogs: [ActivityLog]

    @State private var showCamera = false

    private var activityLogs: [ActivityLog] {
        allLogs.filter { $0.activity?.id == activity.id }
    }

    private var recentLogs: [ActivityLog] {
        Array(activityLogs.prefix(30))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // Photo Timeline (only for photo-metric activities)
                if activity.type == .metric && activity.metricKind == .photo {
                    photoSection
                }

                // Recent History
                historySection
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .navigationTitle(activity.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if activity.type == .metric && activity.metricKind == .photo {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCamera = true } label: {
                        Image(systemName: "camera.fill")
                            .font(.body)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(
                activityID: activity.id,
                activityName: activity.name,
                onCapture: { image in savePhoto(image) }
            )
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: activity.icon)
                .font(.system(size: 36))
                .foregroundStyle(Color(hex: activity.hexColor))

            Text(activity.name)
                .font(.title2.bold())

            if let cat = activity.category {
                Text(cat.name)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: cat.hexColor).opacity(0.2))
                    .foregroundStyle(Color(hex: cat.hexColor))
                    .clipShape(Capsule())
            }

            // Streak
            let streak = currentStreak
            if streak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(streak) day streak")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "photo.stack")
                    .foregroundStyle(.secondary)
                Text("Photo Timeline")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            PhotoTimelineView(
                activityID: activity.id,
                activityName: activity.name
            )
            .frame(minHeight: 200)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text("RECENT HISTORY")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if recentLogs.isEmpty {
                Text("No logs yet")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 12)
            } else {
                ForEach(recentLogs) { log in
                    HStack {
                        Image(systemName: log.status == .completed ? "checkmark.circle.fill" : "forward.fill")
                            .foregroundStyle(log.status == .completed ? .green : .orange)
                            .font(.system(size: 14))

                        Text(log.date.shortDisplay)
                            .font(.subheadline)

                        Spacer()

                        if let val = log.value {
                            Text("\(String(format: "%.1f", val)) \(activity.unit ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if log.status == .skipped, let reason = log.skipReason {
                            Text(reason)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Helpers

    private func savePhoto(_ image: UIImage) {
        guard let filename = MediaService.shared.savePhoto(
            image, activityID: activity.id, date: Date()
        ) else { return }

        // Create a log entry with the photo
        let log = ActivityLog(activity: activity, date: Date(), status: .completed)
        log.photoFilename = filename
        modelContext.insert(log)
    }

    private var currentStreak: Int {
        let completedDates = Set(
            activityLogs
                .filter { $0.status == .completed }
                .map { $0.date.startOfDay }
        )
        var streak = 0
        var day = Date().startOfDay
        while completedDates.contains(day) {
            streak += 1
            guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }
}
