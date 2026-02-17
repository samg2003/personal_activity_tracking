import Foundation
import UIKit

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
        // Include sanitized slot name in filename when provided
        let slotSuffix = slot.map { "_\(Self.sanitize($0))" } ?? ""
        let filename = "\(datePart)\(slotSuffix).jpg"
        let fileURL = activityDir.appendingPathComponent(filename)

        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }

        do {
            try data.write(to: fileURL)
            return "\(activityID.uuidString)/\(filename)"
        } catch {
            return nil
        }
    }

    /// Load a photo by its relative filename
    func loadPhoto(filename: String) -> UIImage? {
        let url = photosDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Get all photo filenames for an activity, sorted chronologically
    func allPhotos(for activityID: UUID) -> [String] {
        let activityDir = photosDirectory.appendingPathComponent(activityID.uuidString)
        guard let files = try? fileManager.contentsOfDirectory(atPath: activityDir.path) else { return [] }
        return files
            .filter { $0.hasSuffix(".jpg") }
            .sorted()
            .map { "\(activityID.uuidString)/\($0)" }
    }

    /// Get all photos for a specific slot, sorted chronologically
    func allPhotos(for activityID: UUID, slot: String) -> [String] {
        let sanitized = Self.sanitize(slot)
        return allPhotos(for: activityID).filter { filename in
            // Match files containing the slot suffix before .jpg
            let base = filename.replacingOccurrences(of: ".jpg", with: "")
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

    /// Extract the slot name from a photo filename (e.g. "UUID/2026-02-12_083000_front-view.jpg" → "front-view")
    /// Returns nil for legacy filenames without a slot suffix.
    static func slotName(from filename: String) -> String? {
        guard let lastComponent = filename.split(separator: "/").last else { return nil }
        let base = lastComponent.replacingOccurrences(of: ".jpg", with: "")
        // Format: yyyy-MM-dd_HHmmss or yyyy-MM-dd_HHmmss_slot-name
        let parts = base.split(separator: "_", maxSplits: 2)
        // 3 parts = date + time + slot
        guard parts.count >= 3 else { return nil }
        return String(parts[2])
    }

    /// Returns all activity UUIDs that have at least one photo
    func allActivityIDsWithPhotos() -> [UUID] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: photosDirectory, includingPropertiesForKeys: nil
        ) else { return [] }

        return contents.compactMap { url -> UUID? in
            guard url.hasDirectoryPath else { return nil }
            let id = UUID(uuidString: url.lastPathComponent)
            // Only include if directory contains at least one jpg
            if let id, let files = try? fileManager.contentsOfDirectory(atPath: url.path),
               files.contains(where: { $0.hasSuffix(".jpg") }) {
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
}
