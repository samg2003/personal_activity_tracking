import SwiftUI
import SwiftData

/// Detail view for an activity: shows photo timeline, camera button, and recent logs
struct ActivityDetailView: View {
    let activity: Activity
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ActivityLog.date, order: .reverse) private var allLogs: [ActivityLog]
    @Query private var vacationDays: [VacationDay]
    @Query(sort: \Activity.sortOrder) private var allActivities: [Activity]

    private let scheduleEngine = ScheduleEngine()

    @State private var showCamera = false

    private var activityLogs: [ActivityLog] {
        allLogs.filter { $0.activity?.id == activity.id }
    }

    private var recentLogs: [ActivityLog] {
        Array(activityLogs.prefix(30))
    }

    private var accentColor: Color { Color(hex: activity.hexColor) }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Gradient hero header
                heroHeader

                // Photo Timeline (only for photo-metric activities)
                if activity.type == .metric && activity.metricKind == .photo {
                    photoSection
                }

                // Recent History
                historySection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
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
                slots: activity.photoSlots
            ) { slotImages in
                savePhotos(slotImages)
            }
        }
    }

    // MARK: - Sections

    private var heroHeader: some View {
        VStack(spacing: 12) {
            // Gradient hero area
            VStack(spacing: 8) {
                Image(systemName: activity.icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(
                        Circle()
                            .fill(.white.opacity(0.2))
                    )

                Text(activity.name)
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                if let cat = activity.category {
                    Text(cat.name)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.2))
                        .foregroundStyle(.white)
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
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.15))
                    .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: WDS.cardRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.7)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: accentColor.opacity(0.2), radius: 10, y: 5)
            )
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeaderPill("Photo Timeline", icon: "photo.stack", color: .purple)

            PhotoTimelineView(
                activityID: activity.id,
                activityName: activity.name
            )
            .frame(minHeight: 200)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeaderPill("Recent History", icon: "clock", color: .blue)

            if recentLogs.isEmpty {
                Text("No logs yet")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(recentLogs) { log in
                    logRow(log)
                }
            }
        }
    }

    // MARK: - Shared Components

    private func sectionHeaderPill(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(color))

            Text(title.uppercased())
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func logRow(_ log: ActivityLog) -> some View {
        HStack(spacing: 0) {
            // Accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(log.status == .completed ? Color.green : Color.orange)
                .frame(width: 4)
                .padding(.vertical, 6)

            HStack(spacing: 10) {
                Image(systemName: log.status == .completed ? "checkmark.circle.fill" : "forward.fill")
                    .foregroundStyle(log.status == .completed ? .green : .orange)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(
                            (log.status == .completed ? Color.green : Color.orange).opacity(0.12)
                        )
                    )

                Text(log.date.shortDisplay)
                    .font(.subheadline.weight(.medium))

                Spacer()

                if let val = log.value {
                    Text("\(String(format: "%.1f", val)) \(activity.unit ?? "")")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                if log.status == .skipped, let reason = log.skipReason {
                    Text(reason)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
        }
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    // MARK: - Helpers

    private func savePhotos(_ slotImages: [String: UIImage]) {
        let date = Date()
        var filenames: [String: String] = [:]
        for (slot, image) in slotImages {
            if let filename = MediaService.shared.savePhoto(image, activityID: activity.id, date: date, slot: slot) {
                filenames[slot] = filename
            }
        }
        guard !filenames.isEmpty else { return }

        let log = ActivityLog(activity: activity, date: date, status: .completed)
        log.photoFilenames = filenames
        log.photoFilename = filenames.values.first  // Legacy compat
        modelContext.insert(log)

        // Pre-generate lapse video in background for instant analytics
        LapseVideoService.shared.preGenerateVideos(activityID: activity.id, photoSlots: activity.photoSlots)
    }

    private var currentStreak: Int {
        scheduleEngine.currentStreak(for: activity, logs: allLogs, allActivities: allActivities, vacationDays: vacationDays)
    }
}
