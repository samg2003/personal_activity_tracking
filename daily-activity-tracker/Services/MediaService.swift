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
}
