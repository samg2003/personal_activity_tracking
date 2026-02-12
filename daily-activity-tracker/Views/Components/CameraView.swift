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
    @State private var capturedImage: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Camera preview
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()

            // Ghost overlay
            if showGhost, let ghost = ghostImage {
                Image(uiImage: ghost)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.3)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Grid lines
            GridOverlay()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Controls
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
                .padding(.bottom, 40)
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

/// Manages AVCaptureSession lifecycle. Uses nonisolated(unsafe) for
/// non-Sendable AVFoundation types that are only used on known queues.
@Observable
final class CameraModel: NSObject {
    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated(unsafe) private let output = AVCapturePhotoOutput()
    nonisolated(unsafe) private var completion: ((UIImage) -> Void)?

    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async { self?.setupSession() }
                }
            }
        default:
            break
        }
    }

    private func setupSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return }
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stop() {
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.stopRunning()
            }
        }
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
        DispatchQueue.main.async { [weak self] in
            self?.completion?(image)
        }
    }
}

// MARK: - Camera Preview (UIViewRepresentable)

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}
