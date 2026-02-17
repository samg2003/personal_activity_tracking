import SwiftUI
import AVKit
import AVFoundation

/// A photo time-lapse viewer that stitches photos into a real video
/// and plays it with AVPlayer for perfectly smooth scrubbing.
struct PhotoLapseView: View {
    let activityID: UUID
    let activityColor: String
    let photoSlots: [String]

    @State private var slotData: [(slot: String, photos: [String])] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if slotData.isEmpty {
                Text("No photos to display")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(slotData, id: \.slot) { entry in
                    SlotVideoSection(
                        slotLabel: entry.slot,
                        photos: entry.photos,
                        cacheKey: "\(activityID.uuidString)_\(entry.slot)",
                        accentColor: Color(hex: activityColor),
                        showLabel: slotData.count > 1,
                        frameDuration: 0.4
                    )
                }
            }
        }
        .onAppear { loadPhotos() }
    }

    private func loadPhotos() {
        let media = MediaService.shared

        if photoSlots.count <= 1 {
            let all = media.allPhotos(for: activityID)
            if !all.isEmpty {
                slotData = [(slot: photoSlots.first ?? "Photos", photos: all)]
            }
        } else {
            slotData = photoSlots.compactMap { slot in
                let sanitized = MediaService.sanitize(slot)
                let photos = media.allPhotos(for: activityID, slot: sanitized)
                return photos.isEmpty ? nil : (slot: slot, photos: photos)
            }
        }
    }
}

// MARK: - Per-Slot Video Section

private struct SlotVideoSection: View {
    let slotLabel: String
    let photos: [String]
    let cacheKey: String
    let accentColor: Color
    let showLabel: Bool
    let frameDuration: Double

    @State private var player: AVPlayer?
    @State private var isGenerating = true
    @State private var currentTime: Double = 0
    @State private var isPlaying = false
    @State private var timeObserver: Any?

    private var totalDuration: Double { Double(photos.count) * frameDuration }
    private var currentIndex: Int {
        min(Int(currentTime / frameDuration), photos.count - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showLabel {
                Text(slotLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)
            }

            // Video player area
            ZStack {
                Color.black

                if isGenerating {
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                        Text("Building time-lapse…")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else if let player {
                    VideoPlayerView(player: player)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Controls
            if !isGenerating {
                VStack(spacing: 6) {
                    // Seek scrubber
                    VideoScrubber(
                        currentTime: $currentTime,
                        duration: totalDuration,
                        accentColor: accentColor,
                        onSeek: { time in
                            seekTo(time)
                        }
                    )

                    // Date + play + counter
                    HStack {
                        if currentIndex < photos.count,
                           let date = MediaService.dateFromFilename(photos[currentIndex]) {
                            Text(date, format: .dateTime.month(.abbreviated).day().year())
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            togglePlayback()
                        } label: {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(accentColor)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text("\(currentIndex + 1) / \(photos.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .onAppear { generateVideo() }
        .onDisappear { cleanup() }
    }

    private func generateVideo() {
        LapseVideoService.shared.generateVideo(photos: photos, cacheKey: cacheKey) { url in
            guard let url else {
                isGenerating = false
                return
            }

            let avPlayer = AVPlayer(url: url)
            avPlayer.actionAtItemEnd = .pause

            // Observe time for scrubber sync
            let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
            let observer = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                if !isSeeking {
                    currentTime = time.seconds
                }
                // Update playing state
                isPlaying = avPlayer.rate > 0
            }

            timeObserver = observer
            player = avPlayer
            isGenerating = false
        }
    }

    @State private var isSeeking = false

    private func seekTo(_ time: Double) {
        guard let player else { return }
        isSeeking = true
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            isSeeking = false
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            // If at end, restart
            if currentTime >= totalDuration - 0.1 {
                seekTo(0)
            }
            player.play()
        }
        isPlaying.toggle()
    }

    private func cleanup() {
        if let observer = timeObserver, let player {
            player.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
    }
}

// MARK: - AVPlayer UIKit wrapper (no default controls)

private struct VideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = PlayerUIView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? PlayerUIView)?.player = player
    }

    private class PlayerUIView: UIView {
        var player: AVPlayer? {
            didSet {
                playerLayer.player = player
                playerLayer.videoGravity = .resizeAspect
            }
        }

        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - Video Scrubber

private struct VideoScrubber: View {
    @Binding var currentTime: Double
    let duration: Double
    let accentColor: Color
    var onSeek: ((Double) -> Void)?

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = duration > 0 ? min(1, max(0, currentTime / duration)) : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray5))
                    .frame(height: 4)

                Capsule()
                    .fill(accentColor)
                    .frame(width: width * fraction, height: 4)

                Circle()
                    .fill(accentColor)
                    .frame(width: isDragging ? 20 : 12, height: isDragging ? 20 : 12)
                    .shadow(color: accentColor.opacity(0.4), radius: isDragging ? 6 : 2)
                    .offset(x: max(0, width * fraction - (isDragging ? 10 : 6)))
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let frac = max(0, min(1, value.location.x / width))
                        let seekTime = frac * duration
                        currentTime = seekTime
                        onSeek?(seekTime)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .animation(.interactiveSpring(response: 0.15), value: isDragging)
        }
        .frame(height: 24)
    }
}
