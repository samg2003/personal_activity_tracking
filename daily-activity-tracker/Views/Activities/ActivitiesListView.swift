import SwiftUI
import SwiftData

/// Full activity management view — edit, reorder, delete, archive
struct ActivitiesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Activity.sortOrder) private var allActivities: [Activity]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var editingActivity: Activity?
    @State private var searchText = ""
    @State private var deleteTarget: Activity?
    @State private var showDeleteAlert = false
    @State private var showAddSheet = false
    @State private var expandedContainers: Set<UUID> = []

    // Top-level activities only (not children of containers)
    private var topLevelActivities: [Activity] {
        allActivities.filter { $0.parent == nil && !$0.isArchived }
    }

    private var archivedActivities: [Activity] {
        allActivities.filter { $0.isArchived }
    }

    private var filteredActivities: [Activity] {
        if searchText.isEmpty { return topLevelActivities }
        return topLevelActivities.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    // Group activities by category
    private var groupedByCategory: [(category: Category?, activities: [Activity])] {
        let dict = Dictionary(grouping: filteredActivities) { $0.category?.id }
        
        var groups: [(category: Category?, activities: [Activity])] = []
        
        // Known categories first (sorted)
        for category in categories {
            if let acts = dict[category.id], !acts.isEmpty {
                groups.append((category: category, activities: acts.sorted { $0.sortOrder < $1.sortOrder }))
            }
        }
        
        // Uncategorized last
        if let acts = dict[nil], !acts.isEmpty {
            groups.append((category: nil, activities: acts.sorted { $0.sortOrder < $1.sortOrder }))
        }
        
        return groups
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedByCategory, id: \.category?.id) { group in
                    Section {
                        ForEach(group.activities) { activity in
                            activityRow(activity)
                        }
                    } header: {
                        categoryHeader(group.category)
                    }
                }

                // Archived section
                if !archivedActivities.isEmpty {
                    Section {
                        DisclosureGroup {
                            ForEach(archivedActivities) { activity in
                                HStack(spacing: 10) {
                                    Image(systemName: activity.icon)
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)

                                    Text(activity.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .strikethrough()

                                    Spacer()

                                    Button {
                                        activity.isArchived = false
                                    } label: {
                                        Text("Restore")
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "archivebox")
                                    .font(.caption)
                                Text("Archived (\(archivedActivities.count))")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Search activities")
            .navigationTitle("Activities")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editingActivity) { activity in
                AddActivityView(activityToEdit: activity)
            }
            .sheet(isPresented: $showAddSheet) {
                AddActivityView()
            }
            .alert("Delete Activity", isPresented: $showDeleteAlert) {
                deleteAlertButtons
            } message: {
                deleteAlertMessage
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func activityRow(_ activity: Activity) -> some View {
        VStack(spacing: 0) {
            activityRowContent(activity)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        initiateDelete(activity)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button {
                        editingActivity = activity
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    if activity.type == .container {
                        Button {
                            cascadeAppearance(activity)
                        } label: {
                            Label("Apply Style to Children", systemImage: "paintbrush")
                        }
                    }

                    Divider()

                    Button {
                        activity.isArchived = true
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }

                    Button(role: .destructive) {
                        initiateDelete(activity)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }

            // Collapsible children for containers
            if activity.type == .container && expandedContainers.contains(activity.id) {
                let children = activity.children.sorted { $0.sortOrder < $1.sortOrder }
                ForEach(children) { child in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color(hex: activity.hexColor).opacity(0.3))
                            .frame(width: 3)
                            .padding(.leading, 12)

                        Button {
                            editingActivity = child
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: child.icon)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(hex: child.hexColor))
                                    .frame(width: 22)

                                Text(child.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)

                                Spacer()

                                infoTags(for: child)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func activityRowContent(_ activity: Activity) -> some View {
        Button {
            if activity.type == .container {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedContainers.contains(activity.id) {
                        expandedContainers.remove(activity.id)
                    } else {
                        expandedContainers.insert(activity.id)
                    }
                }
            } else {
                editingActivity = activity
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: activity.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: activity.hexColor))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(activity.name)
                        .font(.body)
                        .foregroundStyle(.primary)

                    infoTags(for: activity)
                }

                Spacer()

                if activity.type == .container {
                    HStack(spacing: 4) {
                        Text("\(activity.children.count)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Image(systemName: expandedContainers.contains(activity.id) ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Info Tags

    @ViewBuilder
    private func infoTags(for activity: Activity) -> some View {
        FlowLayout(spacing: 4) {
            // Type badge
            tagView(activity.type.rawValue.capitalized, color: Color(hex: activity.hexColor))

            // Schedule
            tagView(scheduleLabel(activity.schedule), color: .secondary, isText: true)

            // Target
            if let target = activity.targetValue {
                let unitStr = activity.unit ?? ""
                tagView("Target: \(formatValue(target))\(unitStr.isEmpty ? "" : " \(unitStr)")", color: .blue)
            }

            // HealthKit
            if activity.healthKitTypeID != nil {
                tagView("HealthKit", color: .red, icon: "heart.fill")
            }

            // Photo
            if activity.allowsPhoto {
                tagView("Photo", color: .purple, icon: "camera.fill")
            }

            // Weight (only if non-default)
            if activity.weight != 1.0 {
                tagView("Weight: \(formatValue(activity.weight))", color: .orange)
            }
        }
    }

    @ViewBuilder
    private func tagView(_ text: String, color: Color, icon: String? = nil, isText: Bool = false) -> some View {
        if isText {
            Text(text)
                .font(.caption2)
                .foregroundStyle(color)
        } else {
            HStack(spacing: 3) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 8))
                }
                Text(text)
            }
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
        }
    }

    // MARK: - Category Header

    @ViewBuilder
    private func categoryHeader(_ category: Category?) -> some View {
        if let cat = category {
            HStack(spacing: 6) {
                Image(systemName: cat.icon)
                    .font(.caption)
                    .foregroundStyle(Color(hex: cat.hexColor))
                Text(cat.name.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
        } else {
            Text("UNCATEGORIZED")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
    }

    // MARK: - Delete Flow

    private func initiateDelete(_ activity: Activity) {
        deleteTarget = activity
        showDeleteAlert = true
    }

    @ViewBuilder
    private var deleteAlertButtons: some View {
        Button("Cancel", role: .cancel) {
            deleteTarget = nil
        }

        if let target = deleteTarget, hasExistingData(target) {
            Button("Archive (Keep Data)") {
                archiveActivity(target)
                deleteTarget = nil
            }
        }

        Button("Delete Everything", role: .destructive) {
            if let target = deleteTarget {
                hardDelete(target)
                deleteTarget = nil
            }
        }
    }

    @ViewBuilder
    private var deleteAlertMessage: some View {
        if let target = deleteTarget {
            if hasExistingData(target) {
                Text("\"\(target.name)\" has \(target.logs.count) log entries. You can archive it (preserves data, hides from dashboard) or delete everything permanently.")
            } else {
                Text("Delete \"\(target.name)\"? This cannot be undone.")
            }
        } else {
            Text("")
        }
    }

    private func hasExistingData(_ activity: Activity) -> Bool {
        !activity.logs.isEmpty || activity.children.contains(where: { !$0.logs.isEmpty })
    }

    private func archiveActivity(_ activity: Activity) {
        let dateStr = Date().formatted(date: .numeric, time: .omitted)
        activity.name = "[Deprecated \(dateStr)] \(activity.name)"
        activity.isArchived = true
    }

    private func hardDelete(_ activity: Activity) {
        // Cascade handles logs and children via @Relationship(deleteRule: .cascade)
        modelContext.delete(activity)
    }

    private func cascadeAppearance(_ container: Activity) {
        for child in container.children {
            child.hexColor = container.hexColor
            child.icon = container.icon
        }
    }

    // MARK: - Helpers

    private func scheduleLabel(_ schedule: Schedule) -> String {
        schedule.type.displayName
    }

    private func formatValue(_ val: Double) -> String {
        val.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", val)
            : String(format: "%.1f", val)
    }
}

/// Simple horizontal flow layout that wraps tags to next line
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
