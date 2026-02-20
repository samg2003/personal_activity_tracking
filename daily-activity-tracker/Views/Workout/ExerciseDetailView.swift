import SwiftUI
import SwiftData
import SafariServices

/// View/edit exercise details — premium styled with WDS design system.
struct ExerciseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var exercise: Exercise
    @Query(sort: \MuscleGroup.sortOrder) private var allMuscles: [MuscleGroup]

    @State private var videoURLToOpen: URL?

    private var accentColor: Color {
        switch exercise.exerciseType {
        case .strength: return WDS.strengthAccent
        case .cardio: return WDS.cardioAccent
        case .timed: return WDS.infoAccent
        }
    }

    private var typeIcon: String {
        switch exercise.exerciseType {
        case .strength: return "dumbbell.fill"
        case .cardio: return "figure.run"
        case .timed: return "timer"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Hero header
                VStack(spacing: 8) {
                    IconBadge(icon: typeIcon, color: accentColor, size: 52)
                    Text(exercise.displayName)
                        .font(.title2.weight(.bold))
                    HStack(spacing: 8) {
                        StatusBadge(text: exercise.exerciseType.displayName, style: .info)
                        if !exercise.equipment.isEmpty {
                            StatusBadge(text: exercise.equipment, style: .draft)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .premiumCard(accent: accentColor)

                // Aliases
                if !exercise.aliases.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle(title: "Aliases")
                        FlowLayout(spacing: 6) {
                            ForEach(exercise.aliases, id: \.self) { alias in
                                Text(alias)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(accentColor.opacity(0.08))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .premiumCard()
                }

                // Muscle Involvements
                if exercise.exerciseType == .strength || exercise.exerciseType == .timed {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(title: "Muscle Involvements")
                        if exercise.muscleInvolvements.isEmpty {
                            Text("No muscles configured")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(exercise.muscleInvolvements) { involvement in
                                HStack(spacing: 8) {
                                    Text(muscleNameFor(involvement))
                                        .font(.subheadline)
                                    Spacer()
                                    // Gradient bar
                                    GeometryReader { geo in
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color(.systemGray5))
                                            .overlay(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 3)
                                                    .fill(involvementGradient(involvement.involvementScore))
                                                    .frame(width: geo.size.width * involvement.involvementScore)
                                            }
                                    }
                                    .frame(width: 70, height: 6)

                                    Text(String(format: "%.0f%%", involvement.involvementScore * 100))
                                        .font(.caption.monospacedDigit().weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 36, alignment: .trailing)
                                }
                            }
                        }
                    }
                    .premiumCard(accent: WDS.strengthAccent)
                }

                // Cardio Config
                if exercise.exerciseType == .cardio {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(title: "Cardio Config")
                        HStack(spacing: 12) {
                            if let unit = exercise.distanceUnit {
                                MetricChip(icon: "ruler", value: unit, label: "Distance", color: WDS.cardioAccent)
                            }
                            if let unit = exercise.paceUnit {
                                MetricChip(icon: "speedometer", value: unit, label: "Pace", color: WDS.cardioAccent)
                            }
                        }
                        if !exercise.availableMetrics.isEmpty {
                            FlowLayout(spacing: 6) {
                                ForEach(exercise.availableMetrics, id: \.self) { metric in
                                    HStack(spacing: 4) {
                                        Image(systemName: metric.icon)
                                            .font(.system(size: 10))
                                        Text(metric.displayName)
                                            .font(.caption2.weight(.medium))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(WDS.cardioAccent.opacity(0.08))
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .premiumCard(accent: WDS.cardioAccent)
                }

                // Notes
                if let notes = exercise.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle(title: "Notes")
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .premiumCard()
                }

                // Videos
                if !exercise.videoURLs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(title: "Videos")
                        ForEach(exercise.videoURLs, id: \.self) { urlString in
                            if let ytID = youtubeVideoID(from: urlString) {
                                Button {
                                    openYouTubeVideo(id: ytID)
                                } label: {
                                    YouTubeThumbnailView(videoID: ytID)
                                }
                                .buttonStyle(ScaleButtonStyle())
                            } else if let url = URL(string: urlString) {
                                Button {
                                    videoURLToOpen = url
                                } label: {
                                    HStack {
                                        Image(systemName: "play.rectangle.fill")
                                            .foregroundStyle(.red)
                                        Text(urlString)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .font(.caption)
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(ScaleButtonStyle())
                            }
                        }
                    }
                    .premiumCard()
                }
            }
            .padding(.horizontal)
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(exercise.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            }
        }
        .sheet(item: $videoURLToOpen) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
    }

    // MARK: - Helpers

    private func muscleNameFor(_ involvement: ExerciseMuscle) -> String {
        guard let muscleID = involvement.muscleGroupID else { return "Unknown" }
        return allMuscles.first { $0.id == muscleID }?.name ?? "Unknown"
    }

    private func involvementGradient(_ score: Double) -> LinearGradient {
        if score >= 0.7 { return LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing) }
        if score >= 0.4 { return LinearGradient(colors: [WDS.strengthAccent, .orange], startPoint: .leading, endPoint: .trailing) }
        return LinearGradient(colors: [.yellow, WDS.strengthAccent.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
    }

    private func openYouTubeVideo(id: String) {
        let youtubeAppURL = URL(string: "youtube://watch?v=\(id)")!
        let webURL = URL(string: "https://www.youtube.com/watch?v=\(id)")!
        if UIApplication.shared.canOpenURL(youtubeAppURL) {
            UIApplication.shared.open(youtubeAppURL)
        } else {
            videoURLToOpen = webURL
        }
    }

    private func youtubeVideoID(from urlString: String) -> String? {
        if let url = URL(string: urlString),
           let host = url.host?.lowercased(),
           (host.contains("youtube.com") || host.contains("youtube-nocookie.com")),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let vParam = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return vParam
        }
        if let url = URL(string: urlString),
           url.host?.lowercased() == "youtu.be" {
            let id = url.lastPathComponent
            return id.isEmpty ? nil : id
        }
        return nil
    }
}

// MARK: - YouTube Thumbnail Preview

struct YouTubeThumbnailView: View {
    let videoID: String

    var body: some View {
        ZStack {
            AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                case .failure:
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .aspectRatio(16/9, contentMode: .fill)
                        .overlay {
                            Image(systemName: "play.rectangle")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                @unknown default:
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .aspectRatio(16/9, contentMode: .fill)
                        .overlay(ProgressView())
                }
            }

            Circle()
                .fill(.red)
                .frame(width: 50, height: 50)
                .overlay {
                    Image(systemName: "play.fill")
                        .foregroundStyle(.white)
                        .font(.title3)
                        .offset(x: 2)
                }
                .shadow(radius: 4)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: WDS.cardRadius, style: .continuous))
    }
}

// FlowLayout is declared in ActivitiesListView.swift

// MARK: - In-App Safari

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
