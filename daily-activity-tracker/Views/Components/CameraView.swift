import SwiftUI
import Observation
@preconcurrency import AVFoundation

/// Camera view with ghost overlay of previous photo for consistent framing
struct CameraView: View {
    let activityID: UUID
    let activityName: String
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraModel()
    @State private var ghostImage: UIImage?
    @State private var showGhost = true
    @State private var ghostOpacity: Double = 0.5
    @State private var showOpacitySlider = false
    @State private var capturedImage: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.state {
            case .idle, .starting:
                // Show spinner while camera initialises
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)

            case .running:
                // Live camera preview
                CameraPreviewView(session: camera.session, isFrontCamera: camera.isFrontCamera)
                    .ignoresSafeArea()

            case .denied:
                permissionDeniedView

            case .unavailable:
                cameraUnavailableView
            }

            // Ghost overlay — match camera preview's aspect-fill crop exactly
            // When front camera, mirror the ghost to match the mirrored preview
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

            // Grid lines (only when camera is running)
            if camera.state == .running {
                GridOverlay()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Controls — always visible so user can dismiss
            VStack {
                // Top bar
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding()
                    }

                    Spacer()

                    Text(activityName)
                        .font(.headline)
                        .foregroundStyle(.white)

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

                // Ghost opacity control (collapsed by default, expands on tap)
                if showGhost, ghostImage != nil, camera.state == .running {
                    HStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showOpacitySlider.toggle()
                            }
                        } label: {
                            Image(systemName: "circle.lefthalf.filled")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial.opacity(0.4))
                                .clipShape(Circle())
                        }

                        if showOpacitySlider {
                            HStack(spacing: 8) {
                                Slider(value: $ghostOpacity, in: 0.1...0.8)
                                    .tint(.yellow)
                                    .frame(width: 140)
                                Text("\(Int(ghostOpacity * 100))%")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.7))
                                    .frame(width: 30)
                            }
                            .padding(.trailing, 10)
                            .padding(.leading, 6)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()

                // Bottom controls (only when camera is running)
                if camera.state == .running {
                    HStack {
                        // Spacer for symmetry
                        Color.clear.frame(width: 44, height: 44)

                        Spacer()

                        // Capture button
                        Button {
                            camera.capturePhoto { image in
                                Task { @MainActor in
                                    capturedImage = image
                                }
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

                        // Flip camera button
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
            ghostImage = MediaService.shared.latestPhoto(for: activityID)
        }
        .onDisappear {
            camera.stop()
        }
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

    // MARK: - Camera Unavailable (e.g. Simulator)

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
                        onCapture(image)
                        dismiss()
                    } label: {
                        Label("Use Photo", systemImage: "checkmark")
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
            .stroke(.white.opacity(0.25), lineWidth: 0.5)
        }
    }
}

// MARK: - Camera Model (AVFoundation)

enum CameraState: Equatable {
    case idle       // Not yet checked permissions
    case starting   // Permission granted, session starting
    case running    // Session is running, preview visible
    case denied     // User denied camera permission
    case unavailable // No camera on device (e.g. simulator)
}

/// Manages AVCaptureSession lifecycle. Uses nonisolated(unsafe) for
/// non-Sendable AVFoundation types that are only used on known queues.
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
            // Try front camera as fallback
            guard let frontDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                state = .unavailable
                return
            }
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
        // Remove existing camera input
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
        // regardless of the mirrored preview — no manual flip needed
        DispatchQueue.main.async { [weak self] in
            self?.completion?(image)
        }
    }
}


// MARK: - Camera Preview (UIViewRepresentable)

/// Uses a custom UIView subclass to keep the preview layer frame in sync via layoutSubviews
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

    /// UIView subclass that keeps its AVCaptureVideoPreviewLayer sized to bounds
    class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
