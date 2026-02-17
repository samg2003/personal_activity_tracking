import SwiftUI
import Observation
@preconcurrency import AVFoundation

// ──────────────────────────────────────────────────────────────────────
// SIDE UTILITY — Self-contained quality comparison tool.
// Only used from PhotoBankView "Help me choose" button.
// Not part of the core capture/save pipeline; safe to ignore or delete.
// ──────────────────────────────────────────────────────────────────────

/// Take one photo, then dynamically pick two format/quality/resolution
/// combos and compare with a reveal slider. Re-encodes on setting change.
struct QualityComparisonView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    enum Phase { case capture, compare }
    @State private var phase: Phase = .capture

    // Camera
    @State private var camera = CameraModel()
    @State private var processing = false

    // Raw captured image (kept in memory for re-encoding)
    @State private var rawImage: UIImage?

    // Settings for comparison sides (user picks after capture)
    @State private var formatA: PhotoFormat = PhotoFormat.current
    @State private var qualityA: PhotoQuality = PhotoQuality.current
    @State private var resolutionA: PhotoSaveResolution = PhotoSaveResolution.current

    @State private var formatB: PhotoFormat = .jpeg
    @State private var qualityB: PhotoQuality = .low
    @State private var resolutionB: PhotoSaveResolution = PhotoSaveResolution.current

    // Encoded results
    @State private var imageA: UIImage?
    @State private var imageB: UIImage?
    @State private var sizeA: String = ""
    @State private var sizeB: String = ""

    // Reveal slider (0 = all B visible, 1 = all A visible)
    @State private var revealAmount: CGFloat = 0.5

    // Zoom & pan
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero

    // Settings panel visibility
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .capture: captureView
                case .compare: compareView
                }
            }
            .navigationTitle(phase == .compare ? "Compare" : "Take a Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                if phase == .compare {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings.toggle()
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Capture

    private var captureView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.state == .running {
                CameraPreviewView(session: camera.session, isFrontCamera: camera.isFrontCamera)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("Starting camera...")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            if processing {
                Color.black.opacity(0.6).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                    Text("Processing...")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
            }

            if camera.state == .running, !processing {
                VStack {
                    // Hint text
                    Text("Take a photo, then compare quality settings")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.top, 12)

                    Spacer()

                    HStack {
                        Color.clear.frame(width: 44, height: 44)
                        Spacer()

                        Button {
                            processing = true
                            camera.capturePhoto { image in
                                handleCapture(image)
                            }
                        } label: {
                            Circle()
                                .fill(.white)
                                .frame(width: 72, height: 72)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 4)
                                        .frame(width: 82, height: 82)
                                )
                        }

                        Spacer()

                        Button {
                            camera.flipCamera()
                        } label: {
                            Image(systemName: "camera.rotate.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.white.opacity(0.15))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 50)
                }
            }
        }
        .onAppear { camera.checkPermissions() }
        .onDisappear { camera.stop() }
    }

    // MARK: - Compare

    private var compareView: some View {
        VStack(spacing: 0) {
            // Image comparison area
            GeometryReader { geo in
                ZStack {
                    if let imageB {
                        Image(uiImage: imageB)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                    }

                    if let imageA {
                        Image(uiImage: imageA)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipShape(RevealClipShape(revealAmount: revealAmount))
                    }

                    // Divider line
                    Rectangle()
                        .fill(.white)
                        .frame(width: 2)
                        .position(x: geo.size.width * revealAmount, y: geo.size.height / 2)
                        .shadow(color: .black.opacity(0.5), radius: 2)

                    // Labels
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("A · \(formatA.rawValue)")
                                .font(.caption2.bold())
                            Text("\(qualityA.rawValue) · \(resolutionA.rawValue)")
                                .font(.caption2)
                            Text(sizeA)
                                .font(.caption2.monospacedDigit())
                        }
                        .padding(6)
                        .background(.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(.leading, 8)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("B · \(formatB.rawValue)")
                                .font(.caption2.bold())
                            Text("\(qualityB.rawValue) · \(resolutionB.rawValue)")
                                .font(.caption2)
                            Text(sizeB)
                                .font(.caption2.monospacedDigit())
                        }
                        .padding(6)
                        .background(.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(.trailing, 8)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
                }
                .scaleEffect(zoomScale)
                .offset(panOffset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoomScale = max(1.0, lastZoomScale * value)
                        }
                        .onEnded { _ in
                            lastZoomScale = zoomScale
                            if zoomScale <= 1.0 {
                                withAnimation(.spring(duration: 0.3)) {
                                    panOffset = .zero
                                    lastPanOffset = .zero
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard zoomScale > 1.0 else { return }
                            panOffset = CGSize(
                                width: lastPanOffset.width + value.translation.width,
                                height: lastPanOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastPanOffset = panOffset
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(duration: 0.3)) {
                        zoomScale = 1.0
                        lastZoomScale = 1.0
                        panOffset = .zero
                        lastPanOffset = .zero
                    }
                }
                .clipped()
            }

            // Bottom controls
            VStack(spacing: 8) {
                Slider(value: $revealAmount, in: 0...1)
                    .padding(.horizontal)

                HStack(spacing: 16) {
                    Button {
                        imageA = nil
                        imageB = nil
                        rawImage = nil
                        processing = false
                        zoomScale = 1.0
                        lastZoomScale = 1.0
                        panOffset = .zero
                        lastPanOffset = .zero
                        phase = .capture
                        camera.checkPermissions()
                    } label: {
                        Label("Retake", systemImage: "camera.rotate")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                    }

                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(.blue)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
    }

    // MARK: - Settings Sheet

    private var settingsSheet: some View {
        NavigationStack {
            List {
                Section("Option A") {
                    Picker("Format", selection: $formatA) {
                        ForEach(PhotoFormat.allCases) { f in Text(f.rawValue).tag(f) }
                    }
                    Picker("Quality", selection: $qualityA) {
                        ForEach(PhotoQuality.allCases) { q in Text(q.rawValue).tag(q) }
                    }
                    Picker("Resolution", selection: $resolutionA) {
                        ForEach(PhotoSaveResolution.allCases) { r in Text(r.rawValue).tag(r) }
                    }
                }

                Section("Option B") {
                    Picker("Format", selection: $formatB) {
                        ForEach(PhotoFormat.allCases) { f in Text(f.rawValue).tag(f) }
                    }
                    Picker("Quality", selection: $qualityB) {
                        ForEach(PhotoQuality.allCases) { q in Text(q.rawValue).tag(q) }
                    }
                    Picker("Resolution", selection: $resolutionB) {
                        ForEach(PhotoSaveResolution.allCases) { r in Text(r.rawValue).tag(r) }
                    }
                }
            }
            .navigationTitle("Comparison Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        showSettings = false
                        reEncode()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Processing

    private func handleCapture(_ capturedImage: UIImage) {
        let isFront = camera.isFrontCamera
        camera.stop()

        DispatchQueue.global(qos: .userInitiated).async {
            // Mirror for front camera to match preview
            let source: UIImage
            if isFront, let cg = capturedImage.cgImage {
                source = UIImage(cgImage: cg, scale: capturedImage.scale, orientation: .leftMirrored)
            } else {
                source = capturedImage
            }

            let media = MediaService.shared

            let preparedA = media.prepareForSaving(source, resolution: resolutionA)
            let dataA = media.encodeImage(preparedA, format: formatA, quality: qualityA)

            let preparedB = media.prepareForSaving(source, resolution: resolutionB)
            let dataB = media.encodeImage(preparedB, format: formatB, quality: qualityB)

            let resultA = dataA.flatMap { UIImage(data: $0) }
            let resultB = dataB.flatMap { UIImage(data: $0) }

            DispatchQueue.main.async {
                rawImage = source
                imageA = resultA
                imageB = resultB
                sizeA = formatSize(dataA?.count ?? 0)
                sizeB = formatSize(dataB?.count ?? 0)
                processing = false
                phase = .compare
            }
        }
    }

    /// Re-encode the stored raw image with current A/B settings
    private func reEncode() {
        guard let raw = rawImage else { return }
        processing = true

        DispatchQueue.global(qos: .userInitiated).async {
            let media = MediaService.shared

            let preparedA = media.prepareForSaving(raw, resolution: resolutionA)
            let dataA = media.encodeImage(preparedA, format: formatA, quality: qualityA)

            let preparedB = media.prepareForSaving(raw, resolution: resolutionB)
            let dataB = media.encodeImage(preparedB, format: formatB, quality: qualityB)

            let resultA = dataA.flatMap { UIImage(data: $0) }
            let resultB = dataB.flatMap { UIImage(data: $0) }

            DispatchQueue.main.async {
                imageA = resultA
                imageB = resultB
                sizeA = formatSize(dataA?.count ?? 0)
                sizeB = formatSize(dataB?.count ?? 0)
                processing = false
            }
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return "\(bytes / 1024) KB"
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
}

// MARK: - Clip Shape

struct RevealClipShape: Shape {
    var revealAmount: CGFloat

    var animatableData: CGFloat {
        get { revealAmount }
        set { revealAmount = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(CGRect(x: 0, y: 0,
                            width: rect.width * revealAmount,
                            height: rect.height))
        return path
    }
}
