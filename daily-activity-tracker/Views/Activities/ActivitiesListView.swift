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
    @State private var removeTarget: Activity?
    @State private var showRemoveDialog = false

    // Inline quick-add state
    @State private var inlineText = ""
    @State private var inlineIsContainer = false
    @State private var inlineContainerText: [UUID: String] = [:]
    @FocusState private var inlineFocusedSection: UUID?
    @FocusState private var inlineFocusedContainer: UUID?

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
                            if activity.type == .container {
                                containerSection(activity)
                            } else {
                                standaloneActivityRow(activity)
                            }
                        }

                        // Inline quick-add at bottom of section
                        inlineAddRow(category: group.category)
                    } header: {
                        categoryHeader(group.category)
                    }
                }

                // If no groups exist, still show a quick-add row
                if groupedByCategory.isEmpty {
                    Section {
                        inlineAddRow(category: nil)
                    } header: {
                        Text("GET STARTED")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
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
                                .contextMenu {
                                    Button {
                                        activity.isArchived = false
                                    } label: {
                                        Label("Unarchive", systemImage: "tray.and.arrow.up")
                                    }

                                    Button(role: .destructive) {
                                        initiateDelete(activity)
                                    } label: {
                                        Label("Delete Permanently", systemImage: "trash")
                                    }
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
            .confirmationDialog(
                "Remove from Container",
                isPresented: $showRemoveDialog,
                titleVisibility: .visible
            ) {
                Button("Future Only") {
                    if let child = removeTarget {
                        // Snapshot old parent, then archive
                        let snap = ActivityConfigSnapshot(
                            activity: child,
                            effectiveFrom: child.configSnapshots
                                .compactMap { $0.effectiveUntil }
                                .max()
                                .map { Calendar.current.date(byAdding: .day, value: 1, to: $0) ?? $0 }
                                ?? child.createdDate,
                            effectiveUntil: Calendar.current.date(byAdding: .day, value: -1, to: Date().startOfDay) ?? Date().startOfDay
                        )
                        modelContext.insert(snap)
                        child.parent = nil
                        child.isArchived = true
                    }
                }
                Button("Remove Everywhere", role: .destructive) {
                    if let child = removeTarget {
                        modelContext.delete(child)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\"Future Only\" archives the activity (past data preserved). \"Remove Everywhere\" deletes it and all logs.")
            }
        }
    }

    // MARK: - Container Section (Header Style)

    @ViewBuilder
    private func containerSection(_ container: Activity) -> some View {
        // Header row — styled as section divider
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if expandedContainers.contains(container.id) {
                    expandedContainers.remove(container.id)
                } else {
                    expandedContainers.insert(container.id)
                }
            }
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: container.hexColor))
                    .frame(width: 4, height: 28)

                Image(systemName: container.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: container.hexColor))

                Text(container.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("\(container.children.count)")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color(hex: container.hexColor).opacity(0.15))
                    .foregroundStyle(Color(hex: container.hexColor))
                    .clipShape(Capsule())

                Spacer()

                Button {
                    if !expandedContainers.contains(container.id) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedContainers.insert(container.id)
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        inlineFocusedContainer = container.id
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(hex: container.hexColor).opacity(0.6))
                }
                .buttonStyle(.plain)

                Image(systemName: expandedContainers.contains(container.id) ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                editingActivity = container
            } label: {
                Label("Edit Container", systemImage: "pencil")
            }

            Button {
                cascadeAppearance(container)
            } label: {
                Label("Apply Style to Children", systemImage: "paintbrush")
            }

            Divider()

            Button {
                container.isArchived = true
            } label: {
                Label("Archive", systemImage: "archivebox")
            }

            Button(role: .destructive) {
                initiateDelete(container)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }

        // Expanded children
        if expandedContainers.contains(container.id) {
            let children = container.children.sorted { $0.sortOrder < $1.sortOrder }
            ForEach(children) { child in
                childActivityRow(child, containerColor: Color(hex: container.hexColor))
            }

            // Inline quick-add for sub-activities
            inlineChildAddRow(container: container)
        }
    }

    // MARK: - Child Activity Row

    @ViewBuilder
    private func childActivityRow(_ child: Activity, containerColor: Color) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(containerColor.opacity(0.25))
                .frame(width: 3)
                .padding(.leading, 8)

            HStack(spacing: 10) {
                Image(systemName: child.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: child.hexColor))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(child.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    infoTags(for: child)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                editingActivity = child
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                initiateDelete(child)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                editingActivity = child
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                editingActivity = child
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button {
                removeTarget = child
                showRemoveDialog = true
            } label: {
                Label("Remove from Container", systemImage: "arrow.up.right.square")
            }

            Divider()

            if child.isStopped {
                Button {
                    child.stoppedAt = nil
                } label: {
                    Label("Resume Tracking", systemImage: "play.fill")
                }
            } else {
                Button {
                    child.stoppedAt = Date().startOfDay
                } label: {
                    Label("Stop Tracking", systemImage: "pause.fill")
                }
            }

            Button {
                child.isArchived = true
            } label: {
                Label("Archive", systemImage: "archivebox")
            }

            Button(role: .destructive) {
                initiateDelete(child)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Standalone Activity Row

    @ViewBuilder
    private func standaloneActivityRow(_ activity: Activity) -> some View {
        Button {
            editingActivity = activity
        } label: {
            HStack(spacing: 12) {
                Image(systemName: activity.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: activity.hexColor))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(activity.name)
                            .font(.body)
                            .foregroundStyle(activity.isStopped ? .secondary : .primary)

                        if activity.isStopped {
                            Text("Stopped")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }

                    infoTags(for: activity)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
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

            Divider()

            if activity.isStopped {
                Button {
                    activity.stoppedAt = nil
                } label: {
                    Label("Resume Tracking", systemImage: "play.fill")
                }
            } else {
                Button {
                    activity.stoppedAt = Date().startOfDay
                } label: {
                    Label("Stop Tracking", systemImage: "pause.fill")
                }
            }

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
    }

    // MARK: - Inline Quick-Add

    @ViewBuilder
    private func inlineAddRow(category: Category?) -> some View {
        let sectionID = category?.id ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        HStack(spacing: 8) {
            Image(systemName: inlineIsContainer ? "folder.badge.plus" : "plus.circle")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)

            TextField(inlineIsContainer ? "New container…" : "New activity…", text: $inlineText)
                .font(.subheadline)
                .textFieldStyle(.plain)
                .focused($inlineFocusedSection, equals: sectionID)
                .onSubmit {
                    let trimmed = inlineText.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    quickCreateActivity(name: trimmed, isContainer: inlineIsContainer, category: category)
                    inlineText = ""
                }

            // Type toggle pill
            Button {
                inlineIsContainer.toggle()
            } label: {
                Text(inlineIsContainer ? "Container" : "Activity")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(inlineIsContainer ? Color.orange.opacity(0.15) : Color.blue.opacity(0.12))
                    .foregroundStyle(inlineIsContainer ? .orange : .blue)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func inlineChildAddRow(container: Activity) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color(hex: container.hexColor).opacity(0.25))
                .frame(width: 3)
                .padding(.leading, 8)

            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: container.hexColor).opacity(0.5))

                TextField("Add sub-activity…", text: Binding(
                    get: { inlineContainerText[container.id] ?? "" },
                    set: { inlineContainerText[container.id] = $0 }
                ))
                .font(.caption)
                .textFieldStyle(.plain)
                .focused($inlineFocusedContainer, equals: container.id)
                .onSubmit {
                    let trimmed = (inlineContainerText[container.id] ?? "").trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    quickCreateChildActivity(name: trimmed, parent: container)
                    inlineContainerText[container.id] = ""
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
        }
    }

    // MARK: - Quick Create Helpers

    private func quickCreateActivity(name: String, isContainer: Bool, category: Category?) {
        let nextSort = (allActivities.map(\.sortOrder).max() ?? 0) + 1
        let type: ActivityType = isContainer ? .container : .checkbox
        let appearance = ActivityAppearance.suggest(for: name, type: type)
        let activity = Activity(
            name: name,
            icon: appearance.icon,
            hexColor: appearance.color,
            type: type,
            schedule: .daily,
            category: category,
            sortOrder: nextSort
        )
        modelContext.insert(activity)
    }

    private func quickCreateChildActivity(name: String, parent: Activity) {
        let nextSort = (parent.children.map(\.sortOrder).max() ?? 0) + 1
        let appearance = ActivityAppearance.suggest(for: name, type: .checkbox)
        let child = Activity(
            name: name,
            icon: appearance.icon,
            hexColor: appearance.color,
            type: .checkbox,
            schedule: .daily,
            sortOrder: nextSort
        )
        child.parent = parent
        modelContext.insert(child)
    }

    // MARK: - Info Tags

    @ViewBuilder
    private func infoTags(for activity: Activity) -> some View {
        FlowLayout(spacing: 4) {
            // Type badge
            tagView(activity.type.rawValue.capitalized, color: Color(hex: activity.hexColor))

            // Schedule
            tagView(scheduleLabel(activity.schedule), color: .secondary, isText: true)

            // Time slot
            if let tw = activity.timeWindow, tw.slot != .allDay {
                tagView(tw.slot.displayName, color: .indigo, icon: tw.slot.icon)
            }

            // Multi-session
            if activity.isMultiSession {
                let count = activity.timeSlots.count
                tagView("\(count)× Daily", color: .teal, icon: "arrow.triangle.2.circlepath")
            }

            // Target
            if let target = activity.targetValue {
                let unitStr = activity.unit ?? ""
                tagView("Target: \(formatValue(target))\(unitStr.isEmpty ? "" : " \(unitStr)")", color: .blue)
            }

            // HealthKit
            if activity.healthKitTypeID != nil {
                tagView("HealthKit", color: .red, icon: "heart.fill")
            }

            // Metric kind
            if activity.type == .metric, let kind = activity.metricKind {
                tagView(kind.displayName, color: .purple, icon: kind.systemImage)
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
        activity.isArchived = true
        // Cascade archive to children so they don't appear as orphans
        if activity.type == .container {
            for child in activity.children {
                child.isArchived = true
            }
        }
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
