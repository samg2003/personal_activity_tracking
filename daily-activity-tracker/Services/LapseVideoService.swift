import AVFoundation
import UIKit

/// Available video resolution options for time-lapse generation
enum VideoResolution: String, CaseIterable, Identifiable {
    case p720 = "720p"
    case p1080 = "1080p"
    case k2 = "2K"
    case k4 = "4K"

    var id: String { rawValue }

    var maxWidth: CGFloat {
        switch self {
        case .p720: return 720
        case .p1080: return 1080
        case .k2: return 2560
        case .k4: return 3840
        }
    }

    static let defaultResolution: VideoResolution = .k2
    static let userDefaultsKey = "lapseVideoResolution"

    static var current: VideoResolution {
        get {
            guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
                  let res = VideoResolution(rawValue: raw) else { return .defaultResolution }
            return res
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
        }
    }
}

/// Stitches an array of photos into a video file for smooth time-lapse playback.
final class LapseVideoService {
    static let shared = LapseVideoService()
    private init() {}

    private let queue = DispatchQueue(label: "com.simplyloop.lapsevideo", qos: .userInitiated)
    private var cache: [String: URL] = [:] // cacheKey -> video URL

    /// Duration each photo is shown in the video (seconds)
    private let frameDuration: Double = 0.4

    /// Generate a time-lapse video from photos. Returns the file URL on completion.
    /// Cached on disk — survives app restarts. Only regenerates when photo count changes.
    /// `progress` is called on main thread with (currentFrame, totalFrames).
    func generateVideo(
        photos: [String],
        cacheKey: String,
        progress: ((Int, Int) -> Void)? = nil,
        completion: @escaping (URL?) -> Void
    ) {
        let filename = "\(cacheKey).mp4"
        let fileURL = cacheDirectory().appendingPathComponent(filename)

        // Check in-memory cache first
        if let cached = cache[cacheKey], FileManager.default.fileExists(atPath: cached.path) {
            completion(cached)
            return
        }

        // Check disk cache (survives app restart)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            cache[cacheKey] = fileURL
            completion(fileURL)
            return
        }

        // Clean up old versions with different photo counts
        cleanStaleVideos(baseKey: cacheKey)

        queue.async { [weak self] in
            guard let self else { return }
            let url = self.buildVideo(from: photos, outputURL: fileURL, progress: progress)
            DispatchQueue.main.async {
                if let url {
                    self.cache[cacheKey] = url
                }
                completion(url)
            }
        }
    }

    /// Invalidate cached video for a given key
    func invalidate(cacheKey: String) {
        if let url = cache.removeValue(forKey: cacheKey) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// List all cached lapse videos with their file sizes
    func cachedVideos() -> [(name: String, size: String, url: URL)] {
        let dir = cacheDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return files
            .filter { $0.hasSuffix(".mp4") }
            .sorted()
            .compactMap { filename in
                let url = dir.appendingPathComponent(filename)
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let bytes = attrs[.size] as? Int64 else { return nil }
                let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                let label = filename.replacingOccurrences(of: ".mp4", with: "")
                return (name: label, size: size, url: url)
            }
    }

    /// Total size of all cached lapse videos in bytes
    func totalCacheSize() -> Int64 {
        let dir = cacheDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return 0 }
        return files.reduce(Int64(0)) { total, filename in
            let path = dir.appendingPathComponent(filename).path
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
            return total + size
        }
    }

    /// Delete all cached lapse videos
    func clearAllCache() {
        let dir = cacheDirectory()
        if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for file in files {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
            }
        }
        cache.removeAll()
    }

    /// Remove old videos that share the same base key but different photo count
    private func cleanStaleVideos(baseKey: String) {
        // baseKey format: "UUID_Slot_Count" — extract the prefix before count
        let parts = baseKey.split(separator: "_")
        guard parts.count >= 2 else { return }
        let prefix = parts.dropLast().joined(separator: "_")
        let dir = cacheDirectory()
        if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for file in files where file.hasPrefix(prefix) && file.hasSuffix(".mp4") {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
            }
        }
    }

    // MARK: - Video Builder

    private func buildVideo(from photos: [String], outputURL: URL, progress: ((Int, Int) -> Void)? = nil) -> URL? {
        guard !photos.isEmpty else { return nil }

        // Determine video size from the first image only, then release it
        let videoSize: CGSize
        if let first = MediaService.shared.loadPhoto(filename: photos[0]) {
            let w = min(first.size.width, VideoResolution.current.maxWidth)
            let scale = w / first.size.width
            videoSize = CGSize(width: w, height: (first.size.height * scale).rounded(.down))
        } else {
            return nil
        }

        try? FileManager.default.removeItem(at: outputURL)

        guard let writer = try? AVAssetWriter(url: outputURL, fileType: .mp4) else { return nil }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(videoSize.width),
            AVVideoHeightKey: Int(videoSize.height),
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(videoSize.width),
                kCVPixelBufferHeightKey as String: Int(videoSize.height),
            ]
        )

        writer.add(writerInput)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: CMTime.zero)

        let frameCMTime = CMTimeMake(value: Int64(frameDuration * 600), timescale: 600)
        let total = photos.count

        // Stream one image at a time — never hold more than one in memory
        for index in 0..<photos.count {
            autoreleasepool {
                let presentationTime = CMTimeMultiply(frameCMTime, multiplier: Int32(index))

                while !writerInput.isReadyForMoreMediaData {
                    Thread.sleep(forTimeInterval: 0.01)
                }

                guard let image = MediaService.shared.loadPhoto(filename: photos[index]),
                      let buffer = pixelBuffer(from: image, size: videoSize) else { return }
                adaptor.append(buffer, withPresentationTime: presentationTime)

                // Report progress on main thread
                if let progress {
                    let current = index + 1
                    DispatchQueue.main.async {
                        progress(current, total)
                    }
                }
            }
        }

        writerInput.markAsFinished()

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()

        return writer.status == AVAssetWriter.Status.completed ? outputURL : nil
    }

    /// Normalize UIImage orientation so cgImage pixels match visual orientation.
    private func normalizeOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(at: .zero)
        }
    }

    private func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        // Bake orientation into pixels before extracting cgImage
        let oriented = normalizeOrientation(image)

        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        // Black background
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        // Draw orientation-corrected image scaled to fit (no crop)
        guard let cgImage = oriented.cgImage else { return nil }
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        let fitScale = min(size.width / imgW, size.height / imgH)
        let drawW = imgW * fitScale
        let drawH = imgH * fitScale
        let drawRect = CGRect(
            x: (size.width - drawW) / 2,
            y: (size.height - drawH) / 2,
            width: drawW,
            height: drawH
        )
        context.draw(cgImage, in: drawRect)

        return buffer
    }

    private func cacheDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("LapseVideos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
