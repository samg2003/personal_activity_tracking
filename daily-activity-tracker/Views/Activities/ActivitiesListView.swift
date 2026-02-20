import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
    @State private var showAddReminderSheet = false
    @State private var expandedContainers: Set<UUID> = []
    @State private var removeTarget: Activity?
    @State private var showRemoveDialog = false

    // Group into Container state
    @State private var selectedForGroup: Set<UUID> = []
    @State private var pendingGroupIds: Set<UUID> = []  // snapshot before dialog
    @State private var showGroupNameAlert = false
    @State private var groupContainerName = ""
    @State private var groupTargetCategory: Category?
    @State private var showGroupCategoryPicker = false

    // Batch category assignment state
    @State private var showBatchCategoryPicker = false
    @State private var pendingBatchIds: Set<UUID> = []  // snapshot before dialog

    // Inline quick-add state
    @State private var inlineText = ""
    @State private var inlineIsContainer = false
    @State private var inlineType: ActivityType = .checkbox
    @State private var inlineContainerText: [UUID: String] = [:]
    @State private var inlineContainerType: [UUID: ActivityType] = [:]
    @FocusState private var inlineFocusedSection: UUID?
    @FocusState private var inlineFocusedContainer: UUID?

    // Top-level activities only (not children of containers), excluding one-time tasks
    private var topLevelActivities: [Activity] {
        allActivities.filter {
            $0.parent == nil && !$0.isStopped
            && $0.schedule.type != .sticky && $0.schedule.type != .adhoc
        }
    }

    // Active one-time tasks (sticky/adhoc not yet completed)
    private var activeOneTimeTasks: [Activity] {
        allActivities.filter {
            $0.parent == nil && !$0.isStopped
            && ($0.schedule.type == .sticky || $0.schedule.type == .adhoc)
        }
    }

    // Completed one-time tasks (sticky/adhoc that are stopped)
    private var completedOneTimeTasks: [Activity] {
        allActivities.filter {
            $0.isStopped
            && ($0.schedule.type == .sticky || $0.schedule.type == .adhoc)
        }
    }

    // Paused recurring activities only (not one-time tasks)
    private var pausedActivities: [Activity] {
        allActivities.filter {
            $0.isStopped
            && $0.schedule.type != .sticky && $0.schedule.type != .adhoc
        }
    }

    private var filteredActivities: [Activity] {
        if searchText.isEmpty { return topLevelActivities }
        return topLevelActivities.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    // Group activities by category — show ALL categories (empty ones included for quick-add)
    private var groupedByCategory: [(category: Category?, activities: [Activity])] {
        let dict = Dictionary(grouping: filteredActivities) { $0.category?.id }
        
        var populated: [(category: Category?, activities: [Activity])] = []
        var empty: [(category: Category?, activities: [Activity])] = []
        
        for category in categories {
            let acts = dict[category.id] ?? []
            if acts.isEmpty {
                empty.append((category: category, activities: []))
            } else {
                populated.append((category: category, activities: acts.sorted { $0.sortOrder < $1.sortOrder }))
            }
        }
        
        // Uncategorized (only if has activities)
        if let acts = dict[nil], !acts.isEmpty {
            populated.append((category: nil, activities: acts.sorted { $0.sortOrder < $1.sortOrder }))
        }
        
        return populated + empty
    }

    var body: some View {
        NavigationStack {
            activitiesList
                .sheet(item: $editingActivity) { activity in
                    AddActivityView(activityToEdit: activity)
                }
                .sheet(isPresented: $showAddSheet) {
                    AddActivityView()
                }
                .sheet(isPresented: $showAddReminderSheet) {
                    AddActivityView(presetReminder: true)
                }
                .alert("Delete Activity", isPresented: $showDeleteAlert) {
                    deleteAlertButtons
                } message: {
                    deleteAlertMessage
                }
                .alert("Group into Container", isPresented: $showGroupNameAlert) {
                    TextField("Container name", text: $groupContainerName)
                    Button("Create") {
                        groupSelectedActivities()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Selected activities will become children of the new container.")
                }
        }
    }

    // Core list + toolbar + search, kept separate to reduce type-checker pressure
    private var activitiesList: some View {
        List(selection: $selectedForGroup) {
            mainListContent
            oneTimeTasksSection
            emptyStateSection
            completedOneTimeSection
            pausedSection
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search activities")
        .navigationTitle("Activities")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !selectedForGroup.isEmpty {
                    Button {
                        pendingBatchIds = selectedForGroup
                        showBatchCategoryPicker = true
                    } label: {
                        Label("Category", systemImage: "tag")
                    }
                    Button {
                        pendingGroupIds = selectedForGroup
                        startGroupFlow()
                    } label: {
                        Label("Group (\(selectedForGroup.count))", systemImage: "folder.badge.plus")
                    }
                }
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .confirmationDialog(
            "Remove from Container",
            isPresented: $showRemoveDialog,
            titleVisibility: .visible
        ) {
            Button("Make Standalone") {
                if let child = removeTarget {
                    makeStandalone(child)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the activity from its container and place it as a standalone activity.")
        }
        .confirmationDialog(
            "Activities span multiple categories",
            isPresented: $showGroupCategoryPicker,
            titleVisibility: .visible
        ) {
            ForEach(categories) { cat in
                Button(cat.name) {
                    groupTargetCategory = cat
                    groupContainerName = ""
                    showGroupNameAlert = true
                }
            }
            Button("No Category") {
                groupTargetCategory = nil
                groupContainerName = ""
                showGroupNameAlert = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pick the category for the new container. All grouped activities will move to this category.")
        }
        .confirmationDialog(
            "Set Category",
            isPresented: $showBatchCategoryPicker,
            titleVisibility: .visible
        ) {
            ForEach(categories) { cat in
                Button(cat.name) {
                    batchSetCategory(cat)
                }
            }
            Button("No Category") {
                batchSetCategory(nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apply this category to all selected activities.")
        }
    }

    // Simple standalone extraction — just detach from parent
    private func makeStandalone(_ activity: Activity) {
        let nextSort = (allActivities.filter { $0.parent == nil && !$0.isStopped }.map(\.sortOrder).max() ?? 0) + 1
        activity.parent = nil
        activity.sortOrder = nextSort
    }

    // MARK: - Extracted List Sections

    @ViewBuilder
    private var mainListContent: some View {
        ForEach(groupedByCategory, id: \.category?.id) { group in
            Section {
                ForEach(group.activities) { activity in
                    if activity.type == .container {
                        containerSection(activity)
                    } else {
                        standaloneActivityRow(activity)
                    }
                }
                .onMove { indices, newOffset in
                    moveActivities(in: group.category, from: indices, to: newOffset)
                }
                inlineAddRow(category: group.category)
            } header: {
                categoryHeader(group.category)
            }
        }
    }

    @State private var remindersExpanded = false

    @ViewBuilder
    private var oneTimeTasksSection: some View {
        let tasks = activeOneTimeTasks.sorted(by: { $0.createdDate > $1.createdDate })
        Section {
            DisclosureGroup(isExpanded: $remindersExpanded) {
                ForEach(tasks) { activity in
                    HStack(spacing: 10) {
                        Image(systemName: activity.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: activity.hexColor))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.name)
                                .font(.subheadline.weight(.medium))
                            if activity.schedule.type == .adhoc,
                               let date = activity.schedule.specificDate {
                                Text(date, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Sticky")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            activity.stoppedAt = Date()
                        } label: {
                            Label("Done", systemImage: "checkmark.circle.fill")
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            editingActivity = activity
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            editingActivity = activity
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button {
                            activity.stoppedAt = Date()
                        } label: {
                            Label("Mark Done", systemImage: "checkmark.circle")
                        }
                        Button(role: .destructive) {
                            initiateDelete(activity)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } label: {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "bell")
                            .font(.caption)
                        Text("Reminders (\(tasks.count))")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        showAddReminderSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
    }

    @State private var completedOneTimeExpanded = false

    @ViewBuilder
    private var completedOneTimeSection: some View {
        if !completedOneTimeTasks.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $completedOneTimeExpanded) {
                    ForEach(completedOneTimeTasks.sorted(by: { ($0.stoppedAt ?? .distantPast) > ($1.stoppedAt ?? .distantPast) })) { activity in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.green)
                                .frame(width: 24)
                            Text(activity.name)
                                .font(.subheadline)
                                .strikethrough()
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let stopped = activity.stoppedAt {
                                Text(stopped, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                initiateDelete(activity)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                activity.stoppedAt = nil
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.orange)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .font(.caption)
                        Text("Completed (\(completedOneTimeTasks.count))")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyStateSection: some View {
        if groupedByCategory.isEmpty && activeOneTimeTasks.isEmpty {
            Section {
                inlineAddRow(category: nil)
            } header: {
                Text("GET STARTED")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
        }
    }

    @ViewBuilder
    private var pausedSection: some View {
        if !pausedActivities.isEmpty {
            Section {
                DisclosureGroup {
                    ForEach(pausedActivities) { activity in
                        pausedActivityRow(activity)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pause.circle")
                            .font(.caption)
                        Text("Paused (\(pausedActivities.count))")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func pausedActivityRow(_ activity: Activity) -> some View {
        HStack(spacing: 10) {
            Image(systemName: activity.icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let pid = activity.pausedParentId,
                   let parentName = allActivities.first(where: { $0.id == pid })?.name {
                    Text("from \(parentName)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                resumeActivity(activity)
            } label: {
                Text("Resume")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button {
                resumeActivity(activity)
            } label: {
                Label("Resume", systemImage: "play.fill")
            }

            Button(role: .destructive) {
                initiateDelete(activity)
            } label: {
                Label("Delete Permanently", systemImage: "trash")
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
                dissolveContainer(container)
            } label: {
                Label("Dissolve Container", systemImage: "arrow.up.right.and.arrow.down.left")
            }

            Divider()

            Button {
                pauseActivity(container)
            } label: {
                Label("Pause", systemImage: "pause.fill")
            }

            Button(role: .destructive) {
                initiateDelete(container)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .dropDestination(for: ActivityTransfer.self) { items, _ in
            guard let transfer = items.first,
                  let activity = allActivities.first(where: { $0.id == transfer.activityId }),
                  activity.type != .container,
                  activity.id != container.id
            else { return false }
            moveActivity(activity, toContainer: container)
            expandedContainers.insert(container.id)
            return true
        }
        if expandedContainers.contains(container.id) {
            let children = container.children.sorted { $0.sortOrder < $1.sortOrder }
            ForEach(children) { child in
                childActivityRow(child, containerColor: Color(hex: container.hexColor))
            }
            .onMove { indices, newOffset in
                moveChildren(in: container, from: indices, to: newOffset)
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: child.hexColor))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(Color(hex: child.hexColor).opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(child.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    infoTags(for: child)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
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
                makeStandalone(child)
            } label: {
                Label("Make Standalone", systemImage: "arrow.up.right.square")
            }

            // Move to a different container
            let otherContainers = allActivities.filter { $0.type == .container && !$0.isStopped && $0.id != child.parent?.id }
            if !otherContainers.isEmpty {
                Menu {
                    ForEach(otherContainers) { container in
                        Button {
                            moveActivity(child, toContainer: container)
                        } label: {
                            Label(container.name, systemImage: container.icon)
                        }
                    }
                } label: {
                    Label("Move to Container", systemImage: "folder.badge.plus")
                }
            }

            Divider()

            Button {
                pauseActivity(child)
            } label: {
                Label("Pause", systemImage: "pause.fill")
            }

            Button(role: .destructive) {
                initiateDelete(child)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .draggable(ActivityTransfer(activityId: child.id))
    }

    @ViewBuilder
    private func standaloneActivityRow(_ activity: Activity) -> some View {
        Button {
            editingActivity = activity
        } label: {
            HStack(spacing: 12) {
                // Circle icon badge
                Image(systemName: activity.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(activity.isStopped ? .secondary : Color(hex: activity.hexColor))
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill((activity.isStopped ? Color.gray : Color(hex: activity.hexColor)).opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(activity.name)
                            .font(.subheadline.weight(.medium))
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.quaternary)
            }
        }
        .buttonStyle(.plain)
        .draggable(ActivityTransfer(activityId: activity.id))
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

            // Move to Container submenu
            let containers = allActivities.filter { $0.type == .container && !$0.isStopped && $0.id != activity.id }
            if !containers.isEmpty {
                Menu {
                    ForEach(containers) { container in
                        Button {
                            moveActivity(activity, toContainer: container)
                        } label: {
                            Label(container.name, systemImage: container.icon)
                        }
                    }
                } label: {
                    Label("Move to Container", systemImage: "folder.badge.plus")
                }
            }

            // Convert to Container
            if activity.type != .container {
                Button {
                    convertToContainer(activity)
                } label: {
                    Label("Convert to Container", systemImage: "square.stack.3d.up")
                }
            }

            Divider()

            Button {
                pauseActivity(activity)
            } label: {
                Label("Pause", systemImage: "pause.fill")
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
            Image(systemName: inlineType == .container ? "folder.badge.plus" : "plus.circle")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)

            TextField(inlineType == .container ? "New container…" : "New activity…", text: $inlineText)
                .font(.subheadline)
                .textFieldStyle(.plain)
                .focused($inlineFocusedSection, equals: sectionID)
                .onSubmit {
                    let trimmed = inlineText.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    quickCreateActivity(name: trimmed, type: inlineType, category: category)
                    inlineText = ""
                }

            // Type picker menu
            Menu {
                ForEach(ActivityType.allCases) { type in
                    Button {
                        inlineType = type
                    } label: {
                        Label(type.displayName, systemImage: type.systemImage)
                    }
                }
            } label: {
                Text(inlineType.displayName)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(inlineTypeColor.opacity(0.12))
                    .foregroundStyle(inlineTypeColor)
                    .clipShape(Capsule())
            }
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
                // Type picker for sub-activity (same as top-level, minus container)
                Menu {
                    ForEach([ActivityType.checkbox, .value, .cumulative, .metric], id: \.self) { type in
                        Button {
                            inlineContainerType[container.id] = type
                        } label: {
                            Label(type.rawValue.capitalized, systemImage: type == .checkbox ? "checkmark.square" : type == .value ? "number" : type == .cumulative ? "chart.bar" : "gauge.medium")
                        }
                    }
                } label: {
                    let currentType = inlineContainerType[container.id] ?? .checkbox
                    Text(currentType.rawValue.capitalized)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(hex: container.hexColor).opacity(0.15))
                        .clipShape(Capsule())
                }

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
                    let type = inlineContainerType[container.id] ?? .checkbox
                    quickCreateChildActivity(name: trimmed, type: type, parent: container)
                    inlineContainerText[container.id] = ""
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
        }
    }

    // MARK: - Quick Create Helpers

    private func quickCreateActivity(name: String, type: ActivityType, category: Category?) {
        let nextSort = (allActivities.map(\.sortOrder).max() ?? 0) + 1
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
        // Smart unit default for types that use units
        if type == .value || type == .cumulative || type == .metric {
            activity.unit = ActivityAppearance.suggestUnit(for: name)
        }
        if type == .metric {
            activity.carryForward = true
            activity.metricKind = ActivityAppearance.suggestMetricKind(for: name) ?? .value
        }
        modelContext.insert(activity)
    }

    private func quickCreateChildActivity(name: String, type: ActivityType, parent: Activity) {
        let nextSort = (parent.children.map(\.sortOrder).max() ?? 0) + 1
        let appearance = ActivityAppearance.suggest(for: name, type: type)
        let child = Activity(
            name: name,
            icon: appearance.icon,
            hexColor: appearance.color,
            type: type,
            schedule: .daily,
            sortOrder: nextSort
        )
        // Smart unit default for types that use units
        if type == .value || type == .cumulative || type == .metric {
            child.unit = ActivityAppearance.suggestUnit(for: name)
        }
        if type == .metric {
            child.carryForward = true
            child.metricKind = ActivityAppearance.suggestMetricKind(for: name) ?? .value
        }
        child.parent = parent
        child.category = parent.category
        modelContext.insert(child)
    }

    private func batchSetCategory(_ category: Category?) {
        let selected = allActivities.filter { pendingBatchIds.contains($0.id) }
        print("[BatchCategory] pendingBatchIds: \(pendingBatchIds.count), matched: \(selected.count) activities")
        for activity in selected {
            activity.category = category
        }
        try? modelContext.save()
        pendingBatchIds.removeAll()
        selectedForGroup.removeAll()
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
            HStack(spacing: 8) {
                Image(systemName: cat.icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color(hex: cat.hexColor)))

                Text(cat.name.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))

                let count = (groupedByCategory.first { $0.category?.id == cat.id }?.activities.count) ?? 0
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: cat.hexColor))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color(hex: cat.hexColor).opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.gray))

                Text("UNCATEGORIZED")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
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
            Button("Pause (Keep Data)") {
                pauseActivity(target)
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

    private func pauseActivity(_ activity: Activity) {
        activity.stoppedAt = Date().startOfDay
        // Remember parent so it can be restored on resume
        activity.pausedParentId = activity.parent?.id
        activity.parent = nil
        // Cascade pause to children so they don't appear as orphans
        if activity.type == .container {
            for child in activity.children {
                child.stoppedAt = Date().startOfDay
                child.pausedParentId = activity.id
                child.parent = nil
            }
        }
    }

    private func resumeActivity(_ activity: Activity) {
        activity.stoppedAt = nil
        // Restore parent if the original container still exists
        if let pid = activity.pausedParentId,
           let parent = allActivities.first(where: { $0.id == pid && !$0.isStopped }) {
            activity.parent = parent
            activity.sortOrder = (parent.children.map(\.sortOrder).max() ?? 0) + 1
        }
        activity.pausedParentId = nil
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

    // MARK: - Move & Convert

    private func moveActivity(_ activity: Activity, toContainer container: Activity) {
        let nextSort = (container.children.map(\.sortOrder).max() ?? 0) + 1
        activity.parent = container
        activity.sortOrder = nextSort
        if let containerCategory = container.category {
            activity.category = containerCategory
        }
    }

    private func convertToContainer(_ activity: Activity) {
        // Snapshot pre-conversion config so historical analytics are preserved
        let snapshot = ActivityConfigSnapshot(
            activity: activity,
            effectiveFrom: activity.createdDate,
            effectiveUntil: Calendar.current.date(byAdding: .day, value: -1, to: Date().startOfDay) ?? Date().startOfDay
        )
        modelContext.insert(snapshot)
        activity.type = .container
        // Clear fields that don't apply to containers
        activity.targetValue = nil
        activity.healthKitTypeID = nil
        activity.healthKitModeRaw = nil
    }

    private func dissolveContainer(_ container: Activity) {
        let children = container.children

        // Transfer goal links from container to its children
        for link in container.goalLinks {
            guard let goal = link.goal else { continue }
            for child in children {
                // Skip if child is already linked to this goal
                let alreadyLinked = goal.linkedActivities.contains {
                    $0.activity?.id == child.id
                }
                guard !alreadyLinked else { continue }

                let newLink = GoalActivity(
                    goal: goal, activity: child,
                    role: link.role, weight: link.weight
                )
                modelContext.insert(newLink)
            }
            modelContext.delete(link)
        }

        // Reparent children to top-level
        for child in children {
            child.parent = nil
        }
        // Snapshot and convert back
        let snapshot = ActivityConfigSnapshot(
            activity: container,
            effectiveFrom: container.createdDate,
            effectiveUntil: Calendar.current.date(byAdding: .day, value: -1, to: Date().startOfDay) ?? Date().startOfDay
        )
        modelContext.insert(snapshot)
        container.type = .checkbox
    }

    // MARK: - Reorder

    private func moveActivities(in category: Category?, from source: IndexSet, to destination: Int) {
        // Get the sorted activities for this category group
        let activities: [Activity]
        if let cat = category {
            activities = filteredActivities
                .filter { $0.category?.id == cat.id }
                .sorted { $0.sortOrder < $1.sortOrder }
        } else {
            activities = filteredActivities
                .filter { $0.category == nil }
                .sorted { $0.sortOrder < $1.sortOrder }
        }
        var reordered = activities
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, activity) in reordered.enumerated() {
            activity.sortOrder = index
        }
    }

    private func moveChildren(in container: Activity, from source: IndexSet, to destination: Int) {
        var children = container.children.sorted { $0.sortOrder < $1.sortOrder }
        children.move(fromOffsets: source, toOffset: destination)
        for (index, child) in children.enumerated() {
            child.sortOrder = index
        }
    }

    private func groupSelectedActivities() {
        let trimmed = groupContainerName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !pendingGroupIds.isEmpty else { return }

        // Only group standalone top-level activities (not containers or children)
        let validSelected = allActivities.filter {
            pendingGroupIds.contains($0.id)
            && $0.parent == nil
            && $0.type != .container
            && !$0.isStopped
        }
        guard !validSelected.isEmpty else { return }

        // Determine category — use groupTargetCategory if multi-cat was resolved, else inherit first
        let uniqueCategories = Set(validSelected.compactMap { $0.category?.id })
        let category: Category?
        if let target = groupTargetCategory {
            category = target
        } else if uniqueCategories.count <= 1 {
            category = validSelected.first?.category
        } else {
            // Should have been resolved by picker, but fallback to first
            category = validSelected.first?.category
        }

        let nextSort = (allActivities.map(\.sortOrder).max() ?? 0) + 1
        let appearance = ActivityAppearance.suggest(for: trimmed, type: .container)

        let container = Activity(
            name: trimmed,
            icon: appearance.icon,
            hexColor: appearance.color,
            type: .container,
            schedule: .daily,
            category: category,
            sortOrder: nextSort
        )
        modelContext.insert(container)

        for (index, activity) in validSelected.enumerated() {
            activity.parent = container
            activity.category = category
            activity.sortOrder = index
        }

        try? modelContext.save()
        pendingGroupIds.removeAll()
        selectedForGroup.removeAll()
        groupTargetCategory = nil
        expandedContainers.insert(container.id)
    }

    /// Validates selection for grouping and starts the flow
    private func startGroupFlow() {
        print("[GroupFlow] pendingGroupIds = \(pendingGroupIds)")
        let validSelected = allActivities.filter {
            pendingGroupIds.contains($0.id)
            && $0.parent == nil
            && $0.type != .container
            && !$0.isStopped
        }
        print("[GroupFlow] validSelected = \(validSelected.map(\.name))")

        guard !validSelected.isEmpty else { return }

        let uniqueCategories = Set(validSelected.compactMap { $0.category?.id })
        let hasUncategorized = validSelected.contains(where: { $0.category == nil })

        if uniqueCategories.count > 1 || (uniqueCategories.count == 1 && hasUncategorized) {
            // Multi-category — ask user to pick
            showGroupCategoryPicker = true
        } else {
            // Same category — go straight to name prompt
            groupTargetCategory = validSelected.first?.category
            groupContainerName = ""
            showGroupNameAlert = true
        }
    }

    // MARK: - Helpers

    private var inlineTypeColor: Color {
        switch inlineType {
        case .checkbox: return .blue
        case .value: return .green
        case .cumulative: return .teal
        case .container: return .orange
        case .metric: return .purple
        }
    }

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
