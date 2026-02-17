import SwiftUI

/// Side-by-side first vs. latest photo comparison for a photo-metric activity.
/// Shows a segmented slot picker when the activity has multiple photo slots.
struct PhotoComparisonCard: View {
    let activity: Activity

    @State private var selectedSlot: String = ""
    @State private var showOverlay = false

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

                // Overlay comparison button
                if latestPhoto != nil {
                    Button {
                        showOverlay = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.horizontal.below.rectangle")
                            Text("Overlay Compare")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(hex: activity.hexColor))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(hex: activity.hexColor).opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        .fullScreenCover(isPresented: $showOverlay) {
            if let first = firstPhoto, let latest = latestPhoto {
                PhotoRevealOverlay(
                    photos: photos,
                    initialLeftIndex: 0,
                    initialRightIndex: photos.count - 1,
                    accentColor: Color(hex: activity.hexColor)
                )
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
        let base = (String(lastComponent) as NSString).deletingPathExtension
        let parts = base.split(separator: "_")
        guard let datePart = parts.first else { return nil }

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

// MARK: - Photo Reveal Overlay

/// Fullscreen overlay that lets you compare two photos from a timeline
/// using a draggable reveal slider — swipe to see before/after.
struct PhotoRevealOverlay: View {
    let photos: [String]
    let initialLeftIndex: Int
    let initialRightIndex: Int
    let accentColor: Color

    @Environment(\.dismiss) private var dismiss

    @State private var leftIndex: Int = 0
    @State private var rightIndex: Int = 0

    // Date picker
    @State private var showDatePicker = false
    @State private var pickerDate = Date()
    @State private var pickerTarget: PickerTarget = .left
    private enum PickerTarget { case left, right }

    private var leftImage: UIImage? {
        guard photos.indices.contains(leftIndex) else { return nil }
        return MediaService.shared.loadPhoto(filename: photos[leftIndex])
    }

    private var rightImage: UIImage? {
        guard photos.indices.contains(rightIndex) else { return nil }
        return MediaService.shared.loadPhoto(filename: photos[rightIndex])
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
                }

                // Photo selectors
                HStack(spacing: 16) {
                    photoStepper(label: "Left", index: $leftIndex)
                    Spacer()
                    photoStepper(label: "Right", index: $rightIndex)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 12)

                // Shared reveal comparison
                RevealComparisonView(
                    imageA: leftImage,
                    imageB: rightImage,
                    accentColor: accentColor,
                    labelA: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dateLabel(for: leftIndex))
                                .font(.caption2.bold())
                            Text("\(leftIndex + 1) of \(photos.count)")
                                .font(.system(size: 9))
                        }
                        .padding(6)
                        .background(.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    },
                    labelB: {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(dateLabel(for: rightIndex))
                                .font(.caption2.bold())
                            Text("\(rightIndex + 1) of \(photos.count)")
                                .font(.system(size: 9))
                        }
                        .padding(6)
                        .background(.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                )
            }
        }
        .onAppear {
            leftIndex = initialLeftIndex
            rightIndex = initialRightIndex
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                PhotoCalendarView(
                    selectedDate: $pickerDate,
                    photoDates: Set(photos.compactMap { photoDate(for: photos.firstIndex(of: $0) ?? 0) }),
                    accentColor: UIColor(accentColor)
                )
                .padding()
                .navigationTitle("Jump to Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Go") {
                            let idx = closestPhotoIndex(to: pickerDate)
                            switch pickerTarget {
                            case .left: leftIndex = idx
                            case .right: rightIndex = idx
                            }
                            showDatePicker = false
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showDatePicker = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Photo Stepper

    @ViewBuilder
    private func photoStepper(label: String, index: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Button {
                if index.wrappedValue > 0 { index.wrappedValue -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.bold())
                    .foregroundStyle(index.wrappedValue > 0 ? .white : .white.opacity(0.3))
            }

            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text(dateLabel(for: index.wrappedValue))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
            }
            .onLongPressGesture {
                pickerTarget = label == "Left" ? .left : .right
                pickerDate = photoDate(for: index.wrappedValue) ?? Date()
                showDatePicker = true
            }

            Button {
                if index.wrappedValue < photos.count - 1 { index.wrappedValue += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(index.wrappedValue < photos.count - 1 ? .white : .white.opacity(0.3))
            }
        }
    }

    // MARK: - Helpers

    private func dateLabel(for index: Int) -> String {
        guard let date = photoDate(for: index) else { return "" }
        let outputFmt = DateFormatter()
        outputFmt.dateFormat = "MMM d, yyyy"
        return outputFmt.string(from: date)
    }

    private func photoDate(for index: Int) -> Date? {
        guard photos.indices.contains(index),
              let lastComponent = photos[index].split(separator: "/").last else { return nil }
        let base = (String(lastComponent) as NSString).deletingPathExtension
        let parts = base.split(separator: "_")
        guard let datePart = parts.first else { return nil }

        let inputFmt = DateFormatter()
        inputFmt.dateFormat = "yyyy-MM-dd"
        return inputFmt.date(from: String(datePart))
    }

    /// Find the photo index whose date is closest to the target date
    private func closestPhotoIndex(to target: Date) -> Int {
        var bestIndex = 0
        var bestDelta = Double.greatestFiniteMagnitude
        for (i, _) in photos.enumerated() {
            guard let d = photoDate(for: i) else { continue }
            let delta = abs(d.timeIntervalSince(target))
            if delta < bestDelta {
                bestDelta = delta
                bestIndex = i
            }
        }
        return bestIndex
    }
}

// MARK: - Calendar with Photo Date Markers

/// Wraps UICalendarView to show colored dot decorations on dates that have photos.
struct PhotoCalendarView: UIViewRepresentable {
    @Binding var selectedDate: Date
    let photoDates: Set<Date>
    let accentColor: UIColor

    /// Normalize dates to midnight for reliable comparison
    private var normalizedPhotoDates: Set<DateComponents> {
        let cal = Calendar.current
        return Set(photoDates.map { cal.dateComponents([.year, .month, .day], from: $0) })
    }

    func makeUIView(context: Context) -> UICalendarView {
        let calendarView = UICalendarView()
        calendarView.calendar = Calendar.current
        calendarView.delegate = context.coordinator
        calendarView.tintColor = accentColor

        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        let cal = Calendar.current
        selection.selectedDate = cal.dateComponents([.year, .month, .day], from: selectedDate)
        calendarView.selectionBehavior = selection

        return calendarView
    }

    func updateUIView(_ uiView: UICalendarView, context: Context) {
        context.coordinator.photoDates = normalizedPhotoDates
        context.coordinator.accentColor = accentColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, photoDates: normalizedPhotoDates, accentColor: accentColor)
    }

    class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: PhotoCalendarView
        var photoDates: Set<DateComponents>
        var accentColor: UIColor

        init(parent: PhotoCalendarView, photoDates: Set<DateComponents>, accentColor: UIColor) {
            self.parent = parent
            self.photoDates = photoDates
            self.accentColor = accentColor
        }

        // Show a dot on dates that have photos
        func calendarView(
            _ calendarView: UICalendarView,
            decorationFor dateComponents: DateComponents
        ) -> UICalendarView.Decoration? {
            let key = DateComponents(year: dateComponents.year, month: dateComponents.month, day: dateComponents.day)
            if photoDates.contains(key) {
                return .default(color: accentColor)
            }
            return nil
        }

        // Handle date selection
        func dateSelection(
            _ selection: UICalendarSelectionSingleDate,
            didSelectDate dateComponents: DateComponents?
        ) {
            guard let comps = dateComponents,
                  let date = Calendar.current.date(from: comps) else { return }
            parent.selectedDate = date
        }

        func dateSelection(
            _ selection: UICalendarSelectionSingleDate,
            canSelectDate dateComponents: DateComponents?
        ) -> Bool {
            true
        }
    }
}
