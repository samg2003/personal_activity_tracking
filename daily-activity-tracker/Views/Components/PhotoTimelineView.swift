import SwiftUI

/// Scrollable photo timeline with scrub slider for smooth before/after transitions
struct PhotoTimelineView: View {
    let activityID: UUID
    let activityName: String

    @State private var allPhotoPaths: [String] = []
    @State private var selectedIndex: Double = 0
    @State private var fullscreenPhoto: String?

    private let mediaService = MediaService.shared

    var body: some View {
        VStack(spacing: 16) {
            if allPhotoPaths.isEmpty {
                emptyState
            } else {
                photoDisplay
                scrubSlider
                thumbnailStrip
            }
        }
        .onAppear { loadPhotos() }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No photos yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Main Photo Display

    private var photoDisplay: some View {
        ZStack {
            let idx = Int(selectedIndex.rounded())
            let clampedIdx = min(max(idx, 0), allPhotoPaths.count - 1)

            if let image = mediaService.loadPhoto(filename: allPhotoPaths[clampedIdx]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture {
                        fullscreenPhoto = allPhotoPaths[clampedIdx]
                    }
                    .id(clampedIdx) // Force re-render on change
                    .transition(.opacity)
            }
        }
        .frame(maxHeight: 300)
        .animation(.easeInOut(duration: 0.15), value: Int(selectedIndex.rounded()))
    }

    // MARK: - Scrub Slider

    private var scrubSlider: some View {
        VStack(spacing: 4) {
            Slider(
                value: $selectedIndex,
                in: 0...Double(max(allPhotoPaths.count - 1, 0)),
                step: 1
            )
            .tint(.accentColor)

            HStack {
                Text(dateFromFilename(allPhotoPaths.first))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(Int(selectedIndex) + 1) of \(allPhotoPaths.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(dateFromFilename(allPhotoPaths.last))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Thumbnail Strip

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(allPhotoPaths.enumerated()), id: \.offset) { index, path in
                        if let image = mediaService.loadPhoto(filename: path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay {
                                    if Int(selectedIndex.rounded()) == index {
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(.white, lineWidth: 2)
                                    }
                                }
                                .onTapGesture {
                                    withAnimation { selectedIndex = Double(index) }
                                }
                                .id(index)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .onChange(of: selectedIndex) { _, newVal in
                withAnimation {
                    proxy.scrollTo(Int(newVal.rounded()), anchor: .center)
                }
            }
        }
    }

    // MARK: - Helpers

    private func loadPhotos() {
        allPhotoPaths = mediaService.allPhotos(for: activityID)
        if !allPhotoPaths.isEmpty {
            selectedIndex = Double(allPhotoPaths.count - 1)
        }
    }

    /// Extract display date from filename like "UUID/2026-02-12_083000.heic"
    private func dateFromFilename(_ path: String?) -> String {
        guard let path = path else { return "" }
        let filename = path.components(separatedBy: "/").last ?? ""
        let dateStr = (filename as NSString).deletingPathExtension
            .replacingOccurrences(of: "_", with: " ")
        // Return just the date part
        return String(dateStr.prefix(10))
    }
}
