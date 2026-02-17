import SwiftUI

/// A photo time-lapse viewer that plays like a video — photos change
/// in-place driven by a scrubber. No horizontal scrolling.
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
                    SlotLapseSection(
                        slotLabel: entry.slot,
                        photos: entry.photos,
                        accentColor: Color(hex: activityColor),
                        showLabel: slotData.count > 1
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

// MARK: - Per-Slot Lapse Section

/// One in-place video-style timeline for a single photo slot.
/// The scrubber drives which frame (photo) is displayed — no scrolling.
private struct SlotLapseSection: View {
    let slotLabel: String
    let photos: [String]
    let accentColor: Color
    let showLabel: Bool

    @State private var currentIndex: Int = 0
    @State private var isPlaying: Bool = false
    @State private var playTimer: Timer? = nil

    // Preloaded images for instant scrubbing
    @State private var imageCache: [Int: UIImage] = [:]
    @State private var cacheReady = false

    private var photoCount: Int { photos.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showLabel {
                Text(slotLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)
            }

            // Fixed frame — photo changes in-place
            ZStack {
                Color.black

                if let image = imageCache[currentIndex] {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .id(currentIndex)
                        .transition(.opacity.animation(.linear(duration: 0.08)))
                } else if !cacheReady {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Controls
            VStack(spacing: 6) {
                // Scrubber
                LapseScrubber(
                    currentIndex: $currentIndex,
                    totalCount: photoCount,
                    accentColor: accentColor
                )

                // Date + play button + position
                HStack {
                    if currentIndex < photos.count,
                       let date = MediaService.dateFromFilename(photos[currentIndex]) {
                        Text(date, format: .dateTime.month(.abbreviated).day().year())
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Play/pause auto-advance
                    if photoCount > 1 {
                        Button {
                            togglePlayback()
                        } label: {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Text("\(currentIndex + 1) / \(photoCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 4)
            }
        }
        .onAppear { preloadImages() }
        .onDisappear { stopPlayback() }
    }

    // Preload all images into memory for instant scrubbing
    private func preloadImages() {
        DispatchQueue.global(qos: .userInitiated).async {
            var cache: [Int: UIImage] = [:]
            for (index, filename) in photos.enumerated() {
                if let img = MediaService.shared.loadPhoto(filename: filename) {
                    cache[index] = img
                }
            }
            DispatchQueue.main.async {
                imageCache = cache
                cacheReady = true
            }
        }
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        isPlaying = true
        // If at end, restart from beginning
        if currentIndex >= photoCount - 1 {
            currentIndex = 0
        }
        playTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            if currentIndex < photoCount - 1 {
                currentIndex += 1
            } else {
                stopPlayback()
            }
        }
    }

    private func stopPlayback() {
        isPlaying = false
        playTimer?.invalidate()
        playTimer = nil
    }
}

// MARK: - Scrubber

/// A draggable scrubber — like a video timeline seek bar
private struct LapseScrubber: View {
    @Binding var currentIndex: Int
    let totalCount: Int
    let accentColor: Color

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width

            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(Color(.systemGray5))
                    .frame(height: 4)

                // Filled progress
                Capsule()
                    .fill(accentColor)
                    .frame(width: progressWidth(in: width), height: 4)

                // Thumb
                Circle()
                    .fill(accentColor)
                    .frame(width: isDragging ? 20 : 12, height: isDragging ? 20 : 12)
                    .shadow(color: accentColor.opacity(0.4), radius: isDragging ? 6 : 2)
                    .offset(x: thumbOffset(in: width))
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let fraction = max(0, min(1, value.location.x / width))
                        let newIndex = Int(round(fraction * Double(totalCount - 1)))
                        if newIndex != currentIndex {
                            currentIndex = newIndex
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .animation(.interactiveSpring(response: 0.15), value: isDragging)
        }
        .frame(height: 24)
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        guard totalCount > 1 else { return totalWidth }
        return totalWidth * CGFloat(currentIndex) / CGFloat(totalCount - 1)
    }

    private func thumbOffset(in totalWidth: CGFloat) -> CGFloat {
        guard totalCount > 1 else { return 0 }
        let pos = totalWidth * CGFloat(currentIndex) / CGFloat(totalCount - 1)
        let halfThumb: CGFloat = isDragging ? 10 : 6
        return max(0, pos - halfThumb)
    }
}
