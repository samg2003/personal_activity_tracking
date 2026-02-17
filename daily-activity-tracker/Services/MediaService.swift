import Foundation
import UIKit
import UniformTypeIdentifiers

/// User-selectable photo file format
enum PhotoFormat: String, CaseIterable, Identifiable {
    case heic = "HEIC"
    case jpeg = "JPEG"

    var id: String { rawValue }
    var fileExtension: String {
        switch self {
        case .heic: return "heic"
        case .jpeg: return "jpg"
        }
    }

    static let userDefaultsKey = "photoSaveFormat"
    static var current: PhotoFormat {
        get {
            guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
                  let fmt = PhotoFormat(rawValue: raw) else { return .heic }
            return fmt
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey) }
    }
}

/// User-selectable photo save resolution (max dimension)
enum PhotoSaveResolution: String, CaseIterable, Identifiable {
    case p1080 = "1080p"
    case k2 = "2K"
    case k4 = "4K"
    case original = "Original"

    var id: String { rawValue }

    /// Max pixel dimension (longest edge). nil = no resize.
    var maxDimension: CGFloat? {
        switch self {
        case .p1080: return 1080
        case .k2: return 2560
        case .k4: return 3840
        case .original: return nil
        }
    }

    static let userDefaultsKey = "photoSaveResolution"
    static var current: PhotoSaveResolution {
        get {
            guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
                  let res = PhotoSaveResolution(rawValue: raw) else { return .k4 }
            return res
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey) }
    }
}

/// User-selectable compression quality
enum PhotoQuality: String, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case max = "Max"

    var id: String { rawValue }

    /// JPEG compression quality (0.0–1.0)
    var jpegQuality: CGFloat {
        switch self {
        case .low: return 0.5
        case .medium: return 0.7
        case .high: return 0.85
        case .max: return 0.95
        }
    }

    /// HEIC compression quality (flatter curve — lower values still look great)
    var heicQuality: CGFloat {
        switch self {
        case .low: return 0.3
        case .medium: return 0.5
        case .high: return 0.65
        case .max: return 0.8
        }
    }

    /// Estimated file size range string for a given resolution and format
    func estimatedSize(resolution: PhotoSaveResolution, format: PhotoFormat) -> String {
        // Base sizes in MB for a 4K photo at quality=high in JPEG
        let baseMB: Double
        switch resolution {
        case .p1080: baseMB = 0.4
        case .k2:    baseMB = 0.9
        case .k4:    baseMB = 1.8
        case .original: baseMB = 2.5
        }

        let qualityMultiplier: Double
        switch self {
        case .low:    qualityMultiplier = 0.4
        case .medium: qualityMultiplier = 0.7
        case .high:   qualityMultiplier = 1.0
        case .max:    qualityMultiplier = 1.5
        }

        let formatMultiplier: Double = (format == .heic) ? 0.6 : 1.0

        let estimated = baseMB * qualityMultiplier * formatMultiplier
        // Show a range (±30%)
        let low = estimated * 0.7
        let high = estimated * 1.3

        func fmt(_ v: Double) -> String {
            if v < 1.0 {
                return "\(Int(v * 1000))KB"
            } else {
                return String(format: "%.1fMB", v)
            }
        }
        return "\(fmt(low)) – \(fmt(high))"
    }

    static let userDefaultsKey = "photoSaveQuality"
    static var current: PhotoQuality {
        get {
            guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
                  let q = PhotoQuality(rawValue: raw) else { return .high }
            return q
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey) }
    }
}

/// Supported photo extensions for loading/filtering
private let photoExtensions: Set<String> = ["jpg", "jpeg", "heic"]

/// Check if a filename is a supported photo
private func isPhoto(_ filename: String) -> Bool {
    let ext = (filename as NSString).pathExtension.lowercased()
    return photoExtensions.contains(ext)
}

/// Strip the file extension from a photo filename (handles .jpg, .jpeg, .heic)
private func stripPhotoExtension(_ filename: String) -> String {
    let ns = filename as NSString
    let ext = ns.pathExtension.lowercased()
    if photoExtensions.contains(ext) {
        return ns.deletingPathExtension
    }
    return filename
}

/// Handles saving and loading photos for activities
final class MediaService {
    static let shared = MediaService()

    private let fileManager = FileManager.default

    private var photosDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("ActivityPhotos", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Save a photo for a given activity and date. Returns the relative filename.
    func savePhoto(_ image: UIImage, activityID: UUID, date: Date, slot: String? = nil) -> String? {
        let activityDir = photosDirectory.appendingPathComponent(activityID.uuidString, isDirectory: true)
        if !fileManager.fileExists(atPath: activityDir.path) {
            try? fileManager.createDirectory(at: activityDir, withIntermediateDirectories: true)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let datePart = formatter.string(from: date)
        let slotSuffix = slot.map { "_\(Self.sanitize($0))" } ?? ""

        let format = PhotoFormat.current
        let filename = "\(datePart)\(slotSuffix).\(format.fileExtension)"
        let fileURL = activityDir.appendingPathComponent(filename)

        // Resize + normalize orientation/pixel format in one pass
        let prepared = prepareForSaving(image)

        // Encode in the selected format
        guard let data = encodeImage(prepared, format: format) else { return nil }

        do {
            try data.write(to: fileURL)
            return "\(activityID.uuidString)/\(filename)"
        } catch {
            return nil
        }
    }

    /// Load a photo by its relative filename (supports .jpg, .heic)
    func loadPhoto(filename: String) -> UIImage? {
        let url = photosDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Get file size (formatted), resolution label, and format for a photo
    func photoFileInfo(filename: String) -> (size: String, resolution: String, format: String)? {
        let url = photosDirectory.appendingPathComponent(filename)
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let bytes = attrs[.size] as? Int64 else { return nil }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        let ext = url.pathExtension.lowercased()
        let format = ext == "heic" ? "HEC" : "JPG"
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else {
            return (size: size, resolution: "?", format: format)
        }
        let maxDim = max(w, h)
        let res: String
        switch maxDim {
        case ..<960: res = "SD"
        case ..<1400: res = "720p"
        case ..<2200: res = "1080p"
        case ..<3200: res = "2K"
        default: res = "4K"
        }
        return (size: size, resolution: res, format: format)
    }

    /// Get all photo filenames for an activity, sorted chronologically
    func allPhotos(for activityID: UUID) -> [String] {
        let activityDir = photosDirectory.appendingPathComponent(activityID.uuidString)
        guard let files = try? fileManager.contentsOfDirectory(atPath: activityDir.path) else { return [] }
        return files
            .filter { isPhoto($0) }
            .sorted()
            .map { "\(activityID.uuidString)/\($0)" }
    }

    /// Get all photos for a specific slot, sorted chronologically
    func allPhotos(for activityID: UUID, slot: String) -> [String] {
        let sanitized = Self.sanitize(slot)
        return allPhotos(for: activityID).filter { filename in
            let base = stripPhotoExtension(filename)
            return base.hasSuffix("_\(sanitized)")
        }
    }

    /// Get the most recent photo for ghost overlay (optionally slot-specific)
    func latestPhoto(for activityID: UUID, slot: String? = nil) -> UIImage? {
        let photos: [String]
        if let slot {
            photos = allPhotos(for: activityID, slot: slot)
        } else {
            photos = allPhotos(for: activityID)
        }
        guard let latest = photos.last else { return nil }
        return loadPhoto(filename: latest)
    }

    /// Sanitize a slot name for safe use in filenames
    static func sanitize(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    /// Extract the slot name from a photo filename (e.g. "UUID/2026-02-12_083000_front-view.heic" → "front-view")
    /// Returns nil for legacy filenames without a slot suffix.
    static func slotName(from filename: String) -> String? {
        guard let lastComponent = filename.split(separator: "/").last else { return nil }
        let base = stripPhotoExtension(String(lastComponent))
        let parts = base.split(separator: "_", maxSplits: 2)
        guard parts.count >= 3 else { return nil }
        return String(parts[2])
    }

    /// Parse the date from a photo filename
    static func dateFromFilename(_ filename: String) -> Date? {
        guard let lastComponent = filename.split(separator: "/").last else { return nil }
        let base = stripPhotoExtension(String(lastComponent))
        let parts = base.split(separator: "_", maxSplits: 2)
        guard parts.count >= 2 else { return nil }
        let dateTimeStr = "\(parts[0])_\(parts[1])"
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HHmmss"
        return fmt.date(from: dateTimeStr)
    }

    /// Rename a photo's date portion on disk. Returns the new relative filename or nil on failure.
    /// Only changes the date (yyyy-MM-dd), preserving the original time, slot suffix, and file extension.
    func renamePhotoDate(_ filename: String, to newDate: Date) -> String? {
        guard let lastComponent = filename.split(separator: "/").last,
              let dirComponent = filename.split(separator: "/").first else { return nil }

        let lastStr = String(lastComponent)
        let ext = (lastStr as NSString).pathExtension
        let base = stripPhotoExtension(lastStr)
        let parts = base.split(separator: "_", maxSplits: 2)
        guard parts.count >= 2 else { return nil }

        let originalTime = parts[1]

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let newDatePart = dateFmt.string(from: newDate)

        let slotSuffix = parts.count >= 3 ? "_\(parts[2])" : ""
        let newFilename = "\(newDatePart)_\(originalTime)\(slotSuffix).\(ext)"
        let newRelative = "\(dirComponent)/\(newFilename)"

        if filename == newRelative { return filename }

        let oldURL = photosDirectory.appendingPathComponent(filename)
        let newURL = photosDirectory.appendingPathComponent(newRelative)

        guard fileManager.fileExists(atPath: oldURL.path) else { return nil }
        do {
            try fileManager.moveItem(at: oldURL, to: newURL)
            return newRelative
        } catch {
            return nil
        }
    }

    /// Returns all activity UUIDs that have at least one photo
    func allActivityIDsWithPhotos() -> [UUID] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: photosDirectory, includingPropertiesForKeys: nil
        ) else { return [] }

        return contents.compactMap { url -> UUID? in
            guard url.hasDirectoryPath else { return nil }
            let id = UUID(uuidString: url.lastPathComponent)
            if let id, let files = try? fileManager.contentsOfDirectory(atPath: url.path),
               files.contains(where: { isPhoto($0) }) {
                return id
            }
            return nil
        }
    }

    /// Delete specific photos by relative filename
    func deletePhotos(_ filenames: Set<String>) {
        for filename in filenames {
            let url = photosDirectory.appendingPathComponent(filename)
            try? fileManager.removeItem(at: url)
        }
    }

    /// Delete all photos for a given activity
    func deleteAllPhotos(for activityID: UUID) {
        let dir = photosDirectory.appendingPathComponent(activityID.uuidString)
        try? fileManager.removeItem(at: dir)
    }

    /// Total number of photos across all activities
    func totalPhotoCount() -> Int {
        allActivityIDsWithPhotos().reduce(0) { $0 + allPhotos(for: $1).count }
    }

    /// Total disk size of all photos (bytes)
    func totalPhotoSize() -> Int64 {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: photosDirectory, includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for dir in contents where dir.hasDirectoryPath {
            guard let files = try? fileManager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.fileSizeKey]
            ) else { continue }
            for file in files {
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }
        return total
    }

    // MARK: - Private Helpers

    /// Prepare image for saving: resize to user's selected resolution AND normalize
    /// orientation + pixel format in a single renderer pass.
    /// Camera images have non-standard pixel formats (YCbCr, wide color) and orientation
    /// metadata. Drawing through UIGraphicsImageRenderer converts to standard sRGB and
    /// applies orientation, producing a clean image for both JPEG and HEIC encoding.
    private func prepareForSaving(_ image: UIImage) -> UIImage {
        let targetSize: CGSize
        if let maxDim = PhotoSaveResolution.current.maxDimension {
            let longestEdge = max(image.size.width, image.size.height)
            if longestEdge > maxDim {
                let scale = maxDim / longestEdge
                targetSize = CGSize(width: (image.size.width * scale).rounded(.down),
                                    height: (image.size.height * scale).rounded(.down))
            } else {
                targetSize = image.size
            }
        } else {
            targetSize = image.size
        }

        // Scale 1.0 is critical: UIGraphicsImageRenderer defaults to device screen
        // scale (3x on modern iPhones). Without this, a 4K image becomes 12K pixels.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    /// Encode a prepared image in the selected format.
    /// Image must already be normalized via prepareForSaving().
    private func encodeImage(_ preparedImage: UIImage, format: PhotoFormat) -> Data? {
        let quality = PhotoQuality.current
        switch format {
        case .heic:
            guard let cgImage = preparedImage.cgImage else {
                return preparedImage.jpegData(compressionQuality: quality.jpegQuality)
            }
            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(
                data, UTType.heic.identifier as CFString, 1, nil
            ) else { return preparedImage.jpegData(compressionQuality: quality.jpegQuality) }
            let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality.heicQuality]
            CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
            guard CGImageDestinationFinalize(dest) else {
                return preparedImage.jpegData(compressionQuality: quality.jpegQuality)
            }
            return data as Data
        case .jpeg:
            return preparedImage.jpegData(compressionQuality: quality.jpegQuality)
        }
    }
}
