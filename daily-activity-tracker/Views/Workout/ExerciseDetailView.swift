import SwiftUI
import SwiftData
import SafariServices

/// View/edit exercise details — muscle involvements, cardio config, aliases.
struct ExerciseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var exercise: Exercise
    @Query(sort: \MuscleGroup.sortOrder) private var allMuscles: [MuscleGroup]

    @State private var videoURLToOpen: URL?

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Name", value: exercise.name)
                LabeledContent("Equipment", value: exercise.equipment)
                LabeledContent("Type", value: exercise.exerciseType.displayName)
            }

            if !exercise.aliases.isEmpty {
                Section("Aliases") {
                    ForEach(exercise.aliases, id: \.self) { alias in
                        Text(alias)
                    }
                }
            }

            if exercise.exerciseType == .strength || exercise.exerciseType == .timed {
                Section("Muscle Involvements") {
                    if exercise.muscleInvolvements.isEmpty {
                        Text("No muscles configured")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(exercise.muscleInvolvements) { involvement in
                            HStack {
                                Text(muscleNameFor(involvement))
                                Spacer()
                                // Visual bar
                                ProgressView(value: involvement.involvementScore, total: 1.0)
                                    .frame(width: 60)
                                    .tint(involvementColor(involvement.involvementScore))
                                Text(String(format: "%.0f%%", involvement.involvementScore * 100))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                    }
                }
            }

            if exercise.exerciseType == .cardio {
                Section("Cardio Config") {
                    if let unit = exercise.distanceUnit {
                        LabeledContent("Distance Unit", value: unit)
                    }
                    if let unit = exercise.paceUnit {
                        LabeledContent("Pace Unit", value: unit)
                    }
                    if !exercise.availableMetrics.isEmpty {
                        LabeledContent("Metrics") {
                            Text(exercise.availableMetrics.map(\.displayName).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let notes = exercise.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }

            if !exercise.videoURLs.isEmpty {
                Section("Videos") {
                    ForEach(exercise.videoURLs, id: \.self) { urlString in
                        if let ytID = youtubeVideoID(from: urlString) {
                            Button {
                                openYouTubeVideo(id: ytID)
                            } label: {
                                YouTubeThumbnailView(videoID: ytID)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
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
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(exercise.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(item: $videoURLToOpen) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
    }

    private func muscleNameFor(_ involvement: ExerciseMuscle) -> String {
        guard let muscleID = involvement.muscleGroupID else { return "Unknown" }
        return allMuscles.first { $0.id == muscleID }?.name ?? "Unknown"
    }

    private func involvementColor(_ score: Double) -> Color {
        if score >= 0.7 { return .red }
        if score >= 0.4 { return .orange }
        return .yellow
    }

    /// Opens video in YouTube app (leverages Premium), falls back to in-app Safari.
    private func openYouTubeVideo(id: String) {
        let youtubeAppURL = URL(string: "youtube://watch?v=\(id)")!
        let webURL = URL(string: "https://www.youtube.com/watch?v=\(id)")!

        if UIApplication.shared.canOpenURL(youtubeAppURL) {
            UIApplication.shared.open(youtubeAppURL)
        } else {
            videoURLToOpen = webURL
        }
    }

    /// Extracts YouTube video ID from various URL formats.
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

/// Shows YouTube video thumbnail with a play button overlay.
/// Tapping opens in Safari/YouTube app — no WKWebView needed.
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

            // Play button overlay
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - In-App Safari

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// Wraps SFSafariViewController for use in SwiftUI sheets.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
