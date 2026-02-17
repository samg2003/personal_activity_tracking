import SwiftUI
import Observation
@preconcurrency import AVFoundation

/// Camera view with multi-slot sequential capture and per-slot ghost overlay
struct CameraView: View {
    let activityID: UUID
    let activityName: String
    let slots: [String]              // e.g. ["Front", "Left", "Right"]
    let onComplete: ([String: UIImage]) -> Void  // slot name → captured image

    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraModel()
    @State private var ghostImage: UIImage?
    @State private var showGhost = true
    @State private var ghostOpacity: Double = 0.5

    @State private var capturedImage: UIImage?

    // Multi-slot state
    @State private var currentSlotIndex = 0
    @State private var capturedSlots: [String: UIImage] = [:]

    /// Convenience initializer for legacy single-photo usage
    init(activityID: UUID, activityName: String, onCapture: @escaping (UIImage) -> Void) {
        self.activityID = activityID
        self.activityName = activityName
        self.slots = ["Photo"]
        self.onComplete = { images in
            if let image = images.values.first {
                onCapture(image)
            }
        }
    }

    /// Full initializer with named slots
    init(activityID: UUID, activityName: String, slots: [String], onComplete: @escaping ([String: UIImage]) -> Void) {
        self.activityID = activityID
        self.activityName = activityName
        self.slots = slots.isEmpty ? ["Photo"] : slots
        self.onComplete = onComplete
    }

    private var currentSlot: String {
        slots.indices.contains(currentSlotIndex) ? slots[currentSlotIndex] : slots.last ?? "Photo"
    }

    private var isMultiSlot: Bool { slots.count > 1 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.state {
            case .idle, .starting:
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)

            case .running:
                CameraPreviewView(session: camera.session, isFrontCamera: camera.isFrontCamera)
                    .ignoresSafeArea()

            case .denied:
                permissionDeniedView

            case .unavailable:
                cameraUnavailableView
            }

            // Ghost overlay — per-slot
            if camera.state == .running, showGhost, let ghost = ghostImage {
                GeometryReader { geo in
                    Image(uiImage: ghost)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .scaleEffect(x: camera.isFrontCamera ? -1 : 1, y: 1)
                }
                .opacity(ghostOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // Grid lines
            if camera.state == .running {
                GridOverlay()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Vertical ghost opacity slider on right edge
            if camera.state == .running, showGhost, ghostImage != nil {
                VStack(spacing: 8) {
                    Image(systemName: "eye.slash")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))

                    // Rotated slider: top = low opacity, bottom = high opacity
                    Slider(value: $ghostOpacity, in: 0.05...0.8)
                        .tint(.yellow)
                        .frame(width: 160)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 30, height: 160)

                    Image(systemName: "eye.fill")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))

                    Text("\(Int(ghostOpacity * 100))%")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 6)
                .background(.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 8)
            }

            // Controls
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding()
                    }

                    Spacer()

                    VStack(spacing: 2) {
                        Text(activityName)
                            .font(.headline)
                            .foregroundStyle(.white)
                        if isMultiSlot {
                            Text(currentSlot)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.yellow)
                        }
                    }

                    Spacer()

                    Button { showGhost.toggle() } label: {
                        Image(systemName: showGhost ? "person.fill" : "person")
                            .font(.title2)
                            .foregroundStyle(showGhost ? .yellow : .white)
                            .padding()
                    }
                    .opacity(ghostImage != nil ? 1 : 0)
                }
                .background(.ultraThinMaterial.opacity(0.3))

                // Slot progress indicator (multi-slot only)
                if isMultiSlot, camera.state == .running {
                    slotProgressBar
                        .padding(.top, 8)
                }

                Spacer()

                // Bottom controls
                if camera.state == .running {
                    VStack(spacing: 16) {
                        // Skip slot button (multi-slot only, and must have at least 1 captured)
                        if isMultiSlot {
                            Button {
                                advanceToNextSlot()
                            } label: {
                                Text("Skip \(currentSlot)")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }

                        HStack {
                            Color.clear.frame(width: 44, height: 44)

                            Spacer()

                            // Capture button
                            Button {
                                camera.capturePhoto { image in
                                    Task { @MainActor in capturedImage = image }
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .stroke(.white, lineWidth: 4)
                                        .frame(width: 72, height: 72)
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 60, height: 60)
                                }
                            }

                            Spacer()

                            // Flip camera
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
                    }
                    .padding(.bottom, 40)
                }
            }

            // Captured image review
            if let captured = capturedImage {
                capturedImageReview(captured)
            }
        }
        .onAppear {
            camera.checkPermissions()
            loadGhostForCurrentSlot()
        }
        .onDisappear {
            camera.stop()
        }
    }

    // MARK: - Slot Progress Bar

    private var slotProgressBar: some View {
        HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                let isCurrent = index == currentSlotIndex
                let isCaptured = capturedSlots[slot] != nil

                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isCaptured ? Color.green : (isCurrent ? Color.yellow : Color.white.opacity(0.3)))
                        .frame(height: 3)

                    Text(slot)
                        .font(.system(size: 9, weight: isCurrent ? .bold : .regular))
                        .foregroundStyle(isCurrent ? .yellow : .white.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Permission Denied

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.gray)

            Text("Camera Access Required")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text("Enable camera access in Settings to take progress photos.")
                .font(.subheadline)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.15))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Camera Unavailable

    private var cameraUnavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.badge.exclamationmark.fill")
                .font(.system(size: 48))
                .foregroundStyle(.gray)

            Text("Camera Unavailable")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text("No camera was found on this device.")
                .font(.subheadline)
                .foregroundStyle(.gray)
        }
    }

    // MARK: - Captured Image Review

    @ViewBuilder
    private func capturedImageReview(_ image: UIImage) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()

            // Show which slot this is for
            if isMultiSlot {
                VStack {
                    Text(currentSlot)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.5))
                        .clipShape(Capsule())
                        .padding(.top, 60)
                    Spacer()
                }
            }

            VStack {
                Spacer()
                HStack(spacing: 40) {
                    Button {
                        capturedImage = nil // Retake
                    } label: {
                        Label("Retake", systemImage: "arrow.counterclockwise")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }

                    Button {
                        acceptCurrentPhoto(image)
                    } label: {
                        let buttonText = isLastSlot ? "Done" : "Next: \(nextSlotName)"
                        Label(buttonText, systemImage: isLastSlot ? "checkmark" : "arrow.right")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .padding()
                            .background(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Slot Navigation

    private var isLastSlot: Bool {
        currentSlotIndex >= slots.count - 1
    }

    private var nextSlotName: String {
        let next = currentSlotIndex + 1
        return slots.indices.contains(next) ? slots[next] : ""
    }

    private func acceptCurrentPhoto(_ image: UIImage) {
        capturedSlots[currentSlot] = image
        capturedImage = nil

        if isLastSlot {
            finishCapture()
        } else {
            advanceToNextSlot()
        }
    }

    private func advanceToNextSlot() {
        capturedImage = nil
        if currentSlotIndex < slots.count - 1 {
            currentSlotIndex += 1
            loadGhostForCurrentSlot()
        } else {
            // All slots done (or skipped)
            finishCapture()
        }
    }

    private func finishCapture() {
        guard !capturedSlots.isEmpty else {
            dismiss()
            return
        }
        onComplete(capturedSlots)
        dismiss()
    }

    private func loadGhostForCurrentSlot() {
        ghostImage = MediaService.shared.latestPhoto(for: activityID, slot: currentSlot)
    }
}

// MARK: - Grid Overlay

struct GridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Path { path in
                // Vertical thirds
                path.move(to: CGPoint(x: w / 3, y: 0))
                path.addLine(to: CGPoint(x: w / 3, y: h))
                path.move(to: CGPoint(x: 2 * w / 3, y: 0))
                path.addLine(to: CGPoint(x: 2 * w / 3, y: h))
                // Horizontal thirds
                path.move(to: CGPoint(x: 0, y: h / 3))
                path.addLine(to: CGPoint(x: w, y: h / 3))
                path.move(to: CGPoint(x: 0, y: 2 * h / 3))
                path.addLine(to: CGPoint(x: w, y: 2 * h / 3))
            }
            .stroke(.white.opacity(0.15), lineWidth: 0.5)
        }
    }
}

// MARK: - Camera State & Model

enum CameraState: Equatable {
    case idle
    case starting
    case running
    case denied
    case unavailable
}

@Observable
final class CameraModel: NSObject {
    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated(unsafe) private let output = AVCapturePhotoOutput()
    nonisolated(unsafe) private var completion: ((UIImage) -> Void)?
    var state: CameraState = .idle
    var isFrontCamera = false

    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            state = .starting
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.state = .starting
                        self?.setupSession()
                    } else {
                        self?.state = .denied
                    }
                }
            }
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .denied
        }
    }

    private func setupSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            guard let frontDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                state = .unavailable
                return
            }
            isFrontCamera = true
            configureSession(with: frontDevice)
            return
        }
        configureSession(with: device)
    }

    private func configureSession(with device: AVCaptureDevice) {
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            state = .unavailable
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async {
                self?.state = .running
            }
        }
    }

    func stop() {
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.stopRunning()
            }
        }
    }

    func flipCamera() {
        let newPosition: AVCaptureDevice.Position = isFrontCamera ? .back : .front
        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
              let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }

        session.beginConfiguration()
        if let currentInput = session.inputs.first as? AVCaptureDeviceInput {
            session.removeInput(currentInput)
        }
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            isFrontCamera.toggle()
        }
        session.commitConfiguration()
    }

    func capturePhoto(completion: @escaping (UIImage) -> Void) {
        self.completion = completion
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        // AVCapturePhotoOutput returns the true orientation (how others see you)
        DispatchQueue.main.async { [weak self] in
            self?.completion?(image)
        }
    }
}

// MARK: - Camera Preview (UIViewRepresentable)

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var isFrontCamera: Bool

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // Layout handled by PreviewUIView via layerClass
    }

    class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
