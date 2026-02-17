import AVFoundation
import UIKit

/// Stitches an array of photos into a video file for smooth time-lapse playback.
final class LapseVideoService {
    static let shared = LapseVideoService()
    private init() {}

    private let queue = DispatchQueue(label: "com.simplyloop.lapsevideo", qos: .userInitiated)
    private var cache: [String: URL] = [:] // cacheKey -> video URL

    /// Duration each photo is shown in the video (seconds)
    private let frameDuration: Double = 0.4

    /// Generate a time-lapse video from photos. Returns the file URL on completion.
    /// Results are cached in memory by a key derived from the photo list.
    func generateVideo(
        photos: [String],
        cacheKey: String,
        completion: @escaping (URL?) -> Void
    ) {
        // Return cached video if available and file exists
        if let cached = cache[cacheKey], FileManager.default.fileExists(atPath: cached.path) {
            completion(cached)
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            let url = self.buildVideo(from: photos, key: cacheKey)
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

    // MARK: - Video Builder

    private func buildVideo(from photos: [String], key: String) -> URL? {
        // Load all images first, determine output size
        let images: [UIImage] = photos.compactMap { MediaService.shared.loadPhoto(filename: $0) }
        guard !images.isEmpty else { return nil }

        // Use the size of the first image as the video dimensions
        let firstSize = images[0].size
        let videoWidth = min(firstSize.width, 1080)
        let scale = videoWidth / firstSize.width
        let videoHeight = (firstSize.height * scale).rounded(.down)
        let videoSize = CGSize(width: videoWidth, height: videoHeight)

        // Output path
        let outputURL = cacheDirectory().appendingPathComponent("\(key).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        // Setup writer
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
        writer.startSession(atSourceTime: .zero)

        let frameCMTime = CMTimeMake(value: Int64(frameDuration * 600), timescale: 600)

        for (index, image) in images.enumerated() {
            let presentationTime = CMTimeMultiply(frameCMTime, multiplier: Int32(index))

            // Wait for input to be ready
            while !writerInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }

            guard let pixelBuffer = pixelBuffer(from: image, size: videoSize) else { continue }
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }

        writerInput.markAsFinished()

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()

        return writer.status == .completed ? outputURL : nil
    }

    private func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
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

        // Draw image scaled to fit (no crop)
        guard let cgImage = image.cgImage else { return nil }
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
