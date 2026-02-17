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

    /// Save a photo for a given activity and date. Returns the filename.
    func savePhoto(_ image: UIImage, activityID: UUID, date: Date) -> String? {
        let activityDir = photosDirectory.appendingPathComponent(activityID.uuidString, isDirectory: true)
        if !fileManager.fileExists(atPath: activityDir.path) {
            try? fileManager.createDirectory(at: activityDir, withIntermediateDirectories: true)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "\(formatter.string(from: date)).jpg"
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

    /// Get the most recent photo for ghost overlay
    func latestPhoto(for activityID: UUID) -> UIImage? {
        guard let latest = allPhotos(for: activityID).last else { return nil }
        return loadPhoto(filename: latest)
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
