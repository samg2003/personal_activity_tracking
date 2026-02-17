import SwiftUI

/// Side-by-side first vs. latest photo comparison for a photo-metric activity.
/// Shows a segmented slot picker when the activity has multiple photo slots.
struct PhotoComparisonCard: View {
    let activity: Activity

    @State private var selectedSlot: String = ""

    private var slots: [String] { activity.photoSlots }
    private var hasMultipleSlots: Bool { slots.count > 1 }

    /// Photos for the selected slot (or all if single-slot), sorted chronologically
    private var photos: [String] {
        if hasMultipleSlots, !selectedSlot.isEmpty {
            return MediaService.shared.allPhotos(for: activity.id, slot: selectedSlot)
        }
        return MediaService.shared.allPhotos(for: activity.id)
    }

    private var firstPhoto: String? { photos.first }
    private var latestPhoto: String? { photos.count > 1 ? photos.last : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Activity header
            HStack(spacing: 8) {
                Image(systemName: activity.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: activity.hexColor))
                    .frame(width: 24)
                Text(activity.name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(photos.count) photos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Slot picker (segmented, not dropdown)
            if hasMultipleSlots {
                Picker("Slot", selection: $selectedSlot) {
                    ForEach(slots, id: \.self) { slot in
                        Text(slot).tag(slot)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Side-by-side comparison
            if let first = firstPhoto {
                HStack(spacing: 8) {
                    photoColumn(filename: first, label: "First")
                    if let latest = latestPhoto {
                        photoColumn(filename: latest, label: "Latest")
                    }
                }
            } else {
                Text("No photos yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            if selectedSlot.isEmpty, let first = slots.first {
                selectedSlot = first
            }
        }
    }

    // MARK: - Photo Column

    @ViewBuilder
    private func photoColumn(filename: String, label: String) -> some View {
        VStack(spacing: 4) {
            if let image = MediaService.shared.loadPhoto(filename: filename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .aspectRatio(3/4, contentMode: .fill)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(3/4, contentMode: .fill)
            }

            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(label == "Latest" ? Color(hex: activity.hexColor) : .secondary)
                if let date = dateFromFilename(filename) {
                    Text("· \(date)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// Extract a human-readable date (including year) from the photo filename
    private func dateFromFilename(_ filename: String) -> String? {
        guard let lastComponent = filename.split(separator: "/").last else { return nil }
        let base = lastComponent.replacingOccurrences(of: ".jpg", with: "")
        let parts = base.split(separator: "_")
        guard let datePart = parts.first else { return nil }

        // Parse yyyy-MM-dd and format nicely with year
        let inputFmt = DateFormatter()
        inputFmt.dateFormat = "yyyy-MM-dd"
        guard let date = inputFmt.date(from: String(datePart)) else {
            return String(datePart)
        }

        let outputFmt = DateFormatter()
        outputFmt.dateFormat = "MMM d, yyyy"
        return outputFmt.string(from: date)
    }
}
