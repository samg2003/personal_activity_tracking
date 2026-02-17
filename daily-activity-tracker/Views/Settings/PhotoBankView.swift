import SwiftUI
import SwiftData

/// Settings → Photo Bank: browse and manage all captured progress photos, grouped by activity
struct PhotoBankView: View {
    @Query(sort: \Activity.name) private var allActivities: [Activity]

    @State private var activityPhotos: [(activity: Activity, filenames: [String])] = []
    @State private var orphanPhotos: [(activityID: UUID, filenames: [String])] = []
    @State private var totalSize: String = ""

    var body: some View {
        List {
            if activityPhotos.isEmpty && orphanPhotos.isEmpty {
                ContentUnavailableView(
                    "No Photos Yet",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Photos will appear here when you use photo tracking.")
                )
                .listRowBackground(Color.clear)
            }

            if !activityPhotos.isEmpty {
                ForEach(activityPhotos, id: \.activity.id) { item in
                    NavigationLink {
                        ActivityPhotosGridView(
                            activityName: item.activity.name,
                            activityColor: item.activity.hexColor,
                            filenames: item.filenames,
                            photoSlots: item.activity.photoSlots
                        ) {
                            refreshData()
                        }
                    } label: {
                        activityRow(item.activity, count: item.filenames.count, filenames: item.filenames)
                    }
                }
            }

            // Orphaned photos (activity was deleted but photos remain)
            if !orphanPhotos.isEmpty {
                Section("Orphaned Photos") {
                    ForEach(orphanPhotos, id: \.activityID) { item in
                        NavigationLink {
                            ActivityPhotosGridView(
                                activityName: "Deleted Activity",
                                activityColor: "#888888",
                                filenames: item.filenames,
                                photoSlots: []
                            ) {
                                refreshData()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                thumbnailView(filename: item.filenames.last)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Deleted Activity")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Text("\(item.filenames.count) photo\(item.filenames.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()

                                // Quick delete all orphaned
                                Button {
                                    MediaService.shared.deleteAllPhotos(for: item.activityID)
                                    refreshData()
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }

            if !totalSize.isEmpty {
                Section {
                    HStack {
                        Text("Total Storage")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(totalSize)
                            .foregroundStyle(.secondary)
                            .font(.subheadline.monospacedDigit())
                    }
                }
            }
        }
        .navigationTitle("Photo Bank")
        .onAppear { refreshData() }
    }

    // MARK: - Activity Row

    @ViewBuilder
    private func activityRow(_ activity: Activity, count: Int, filenames: [String]) -> some View {
        HStack(spacing: 12) {
            thumbnailView(filename: filenames.last)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: activity.icon)
                        .font(.caption)
                        .foregroundStyle(Color(hex: activity.hexColor))
                    Text(activity.name)
                        .font(.subheadline.weight(.medium))
                }
                Text("\(count) photo\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private func thumbnailView(filename: String?) -> some View {
        if let filename, let image = MediaService.shared.loadPhoto(filename: filename) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
        }
    }

    // MARK: - Data Loading

    private func refreshData() {
        let media = MediaService.shared
        let activityIDs = media.allActivityIDsWithPhotos()
        let activityMap = Dictionary(uniqueKeysWithValues: allActivities.map { ($0.id, $0) })

        var matched: [(activity: Activity, filenames: [String])] = []
        var orphans: [(activityID: UUID, filenames: [String])] = []

        for id in activityIDs {
            let photos = media.allPhotos(for: id)
            guard !photos.isEmpty else { continue }

            if let activity = activityMap[id] {
                matched.append((activity, photos))
            } else {
                orphans.append((id, photos))
            }
        }

        // Sort by activity name
        activityPhotos = matched.sorted { $0.activity.name.localizedCaseInsensitiveCompare($1.activity.name) == .orderedAscending }
        orphanPhotos = orphans

        // Calculate total size
        let bytes = media.totalPhotoSize()
        totalSize = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Photo Grid (per activity, grouped by slot)

/// Grid view of all photos for a single activity, grouped by photo slot
struct ActivityPhotosGridView: View {
    let activityName: String
    let activityColor: String
    let filenames: [String]
    let photoSlots: [String]  // Activity's defined slot names
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var photos: [String] = []
    @State private var previewPhoto: String?

    private let maxPreviewCount = 20

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    /// Groups photos by their sanitized slot suffix, maintaining defined slot order
    private var slotGroups: [(label: String, photos: [String])] {
        guard photoSlots.count > 1 else { return [] }

        var groups: [(label: String, photos: [String])] = []

        for slot in photoSlots {
            let sanitized = MediaService.sanitize(slot)
            let matching = photos.filter { filename in
                MediaService.slotName(from: filename) == sanitized
            }
            if !matching.isEmpty {
                groups.append((slot, matching))
            }
        }

        // Catch any photos without a matching slot (legacy or unrecognized)
        let allGrouped = Set(groups.flatMap(\.photos))
        let ungrouped = photos.filter { !allGrouped.contains($0) }
        if !ungrouped.isEmpty {
            groups.append(("Other", ungrouped))
        }

        return groups
    }

    private var isSingleSlot: Bool { photoSlots.count <= 1 }

    var body: some View {
        ScrollView {
            if photos.isEmpty {
                ContentUnavailableView(
                    "No Photos",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("All photos have been deleted.")
                )
                .padding(.top, 60)
            } else if isSingleSlot {
                // Flat grid for single-slot activities
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(photos, id: \.self) { filename in
                        photoCell(filename)
                    }
                }
                .padding(.horizontal, 2)
            } else {
                // Grouped by slot
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(slotGroups, id: \.label) { group in
                        slotSection(group.label, photos: group.photos)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .navigationTitle(activityName)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $previewPhoto) { filename in
            PhotoPreviewView(filename: filename) { newName in
                if let idx = photos.firstIndex(of: filename) {
                    photos[idx] = newName
                }
            }
        }
        .onAppear { photos = filenames }
    }

    // MARK: - Slot Section

    @ViewBuilder
    private func slotSection(_ label: String, photos: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NavigationLink {
                SlotPhotosView(
                    slotName: label,
                    activityName: activityName,
                    activityColor: activityColor,
                    filenames: photos,
                    onDelete: {
                        self.photos.removeAll { photos.contains($0) }
                        onDelete()
                    }
                )
            } label: {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(photos.count)")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.15))
                        .clipShape(Capsule())
                    Spacer()
                    if photos.count > maxPreviewCount {
                        Text("See All")
                            .font(.caption)
                            .foregroundStyle(Color(hex: activityColor))
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            // Show up to maxPreviewCount photos
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(photos.prefix(maxPreviewCount)), id: \.self) { filename in
                    photoCell(filename)
                }
            }
        }
    }

    // MARK: - Photo Cell

    @ViewBuilder
    private func photoCell(_ filename: String) -> some View {
        Button {
            previewPhoto = filename
        } label: {
            ZStack(alignment: .bottomLeading) {
                if let image = MediaService.shared.loadPhoto(filename: filename) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                } else {
                    Color.gray.opacity(0.2)
                        .aspectRatio(1, contentMode: .fill)
                }

                if let date = dateFromFilename(filename) {
                    Text(date)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func dateFromFilename(_ filename: String) -> String? {
        guard let lastComponent = filename.split(separator: "/").last else { return nil }
        let name = lastComponent.replacingOccurrences(of: ".jpg", with: "")
        let parts = name.split(separator: "_")
        guard let datePart = parts.first else { return nil }
        return String(datePart)
    }
}

// MARK: - Slot Photos (full view with multi-select & delete)

/// Full photo grid for a single slot, with selection and delete capabilities
struct SlotPhotosView: View {
    let slotName: String
    let activityName: String
    let activityColor: String
    let filenames: [String]
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var photos: [String] = []
    @State private var selectedPhotos: Set<String> = []
    @State private var isSelecting = false
    @State private var showDeleteConfirm = false
    @State private var previewPhoto: String?

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        ScrollView {
            if photos.isEmpty {
                ContentUnavailableView(
                    "No Photos",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("All photos for this view have been deleted.")
                )
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(photos, id: \.self) { filename in
                        slotPhotoCell(filename)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .navigationTitle(slotName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !photos.isEmpty {
                    Button(isSelecting ? "Done" : "Select") {
                        isSelecting.toggle()
                        if !isSelecting { selectedPhotos.removeAll() }
                    }
                }
            }
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button(selectedPhotos.count == photos.count ? "Deselect All" : "Select All") {
                        if selectedPhotos.count == photos.count {
                            selectedPhotos.removeAll()
                        } else {
                            selectedPhotos = Set(photos)
                        }
                    }
                    .font(.subheadline)
                }
            }
            if isSelecting && !selectedPhotos.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete \(selectedPhotos.count) Photo\(selectedPhotos.count == 1 ? "" : "s")", systemImage: "trash")
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete \(selectedPhotos.count) photo\(selectedPhotos.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                MediaService.shared.deletePhotos(selectedPhotos)
                photos.removeAll { selectedPhotos.contains($0) }
                selectedPhotos.removeAll()
                isSelecting = false
                onDelete()
                if photos.isEmpty { dismiss() }
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .fullScreenCover(item: $previewPhoto) { filename in
            PhotoPreviewView(filename: filename) { newName in
                if let idx = photos.firstIndex(of: filename) {
                    photos[idx] = newName
                }
            }
        }
        .onAppear { photos = filenames }
    }

    @ViewBuilder
    private func slotPhotoCell(_ filename: String) -> some View {
        let isSelected = selectedPhotos.contains(filename)
        Button {
            if isSelecting {
                if isSelected { selectedPhotos.remove(filename) }
                else { selectedPhotos.insert(filename) }
            } else {
                previewPhoto = filename
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                if let image = MediaService.shared.loadPhoto(filename: filename) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                } else {
                    Color.gray.opacity(0.2)
                        .aspectRatio(1, contentMode: .fill)
                }

                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color(hex: activityColor) : .white)
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color(hex: activityColor), lineWidth: 3)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Photo Preview (fullscreen)

extension String: @retroactive Identifiable {
    public var id: String { self }
}

struct PhotoPreviewView: View {
    let filename: String
    var onRename: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var showDatePicker = false
    @State private var selectedDate: Date = Date()
    @State private var currentFilename: String = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = MediaService.shared.loadPhoto(filename: currentFilename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding()
                    }
                    Spacer()
                }
                Spacer()

                // Date editor bar at bottom
                Button {
                    showDatePicker.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.caption)
                        Text(selectedDate, format: .dateTime.month(.abbreviated).day().year())
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
                .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                DatePicker("Photo Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Change Date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                if let newName = MediaService.shared.renamePhotoDate(currentFilename, to: selectedDate) {
                                    currentFilename = newName
                                    onRename?(newName)
                                }
                                showDatePicker = false
                            }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showDatePicker = false }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            currentFilename = filename
            selectedDate = MediaService.dateFromFilename(filename) ?? Date()
        }
    }
}
