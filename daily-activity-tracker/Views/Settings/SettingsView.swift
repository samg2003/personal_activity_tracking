import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingExportSheet = false
    @State private var showingImportPicker = false
    @State private var showingClearAlert = false
    @State private var exportURL: URL?
    @State private var alertMessage = ""
    @State private var showAlert = false

    // Category management
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @State private var editingCategory: Category?
    @State private var showAddCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryIcon = "folder"
    @State private var newCategoryColor = "#007AFF"

    // Notification state (synced with UserDefaults via NotificationService)
    @State private var morningEnabled = NotificationService.shared.morningConfig.enabled
    @State private var morningTime = Self.dateFrom(NotificationService.shared.morningConfig)
    @State private var afternoonEnabled = NotificationService.shared.afternoonConfig.enabled
    @State private var afternoonTime = Self.dateFrom(NotificationService.shared.afternoonConfig)
    @State private var eveningEnabled = NotificationService.shared.eveningConfig.enabled
    @State private var eveningTime = Self.dateFrom(NotificationService.shared.eveningConfig)

    private static func dateFrom(_ config: NotificationService.DayPartConfig) -> Date {
        Calendar.current.date(from: DateComponents(hour: config.hour, minute: config.minute)) ?? Date()
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    reminderRow(
                        label: "Morning", icon: "sunrise.fill", color: .orange,
                        enabled: $morningEnabled, time: $morningTime
                    )
                    reminderRow(
                        label: "Afternoon", icon: "sun.max.fill", color: .yellow,
                        enabled: $afternoonEnabled, time: $afternoonTime
                    )
                    reminderRow(
                        label: "Evening", icon: "moon.fill", color: .indigo,
                        enabled: $eveningEnabled, time: $eveningTime
                    )
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Get a daily nudge to check your activities.")
                }

                categoriesSection

                Section("Data Management") {
                    Button {
                        exportData()
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }
                    
                    Button {
                        showingImportPicker = true
                    } label: {
                        Label("Import Data", systemImage: "square.and.arrow.down")
                    }
                    
                    Button(role: .destructive) {
                        showingClearAlert = true
                    } label: {
                        Label("Clear All Data", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
                
                Section {
                    Link(destination: URL(string: "https://www.apple.com")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Text("Version 1.0.0")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                } footer: {
                    Text("Daily Activity Tracker © 2026")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingExportSheet) {
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                importData(result: result)
            }
            .alert("Clear Data?", isPresented: $showingClearAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) { clearData() }
            } message: {
                Text("This action cannot be undone. All activities and logs will be permanently deleted.")
            }
            .alert("Result", isPresented: $showAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    // MARK: - Actions
    
    private func exportData() {
        Task {
            do {
                let json = try DataService.shared.exportData(context: modelContext)
                let filename = "DailyTracker_Backup_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).json"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try json.write(to: tempURL, atomically: true, encoding: .utf8)
                self.exportURL = tempURL
                self.showingExportSheet = true
            } catch {
                alertMessage = "Export failed: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    private func importData(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let data = try Data(contentsOf: url)
                if let json = String(data: data, encoding: .utf8) {
                    try DataService.shared.restoreData(json: json, context: modelContext)
                    alertMessage = "Data restored successfully!"
                    showAlert = true
                }
            } catch {
                alertMessage = "Import failed: \(error.localizedDescription)"
                showAlert = true
            }
        case .failure(let error):
            alertMessage = "Import failed: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    private func clearData() {
        do {
            // Safe Deletion: Fetch and delete objects explicitly
            // 1. Delete Logs (Depend on Activity)
            let logs = try modelContext.fetch(FetchDescriptor<ActivityLog>())
            for log in logs { modelContext.delete(log) }
            
            // 2. Delete Activities (Depend on Category - optional, Parent - self)
            let activities = try modelContext.fetch(FetchDescriptor<Activity>())
            for activity in activities { modelContext.delete(activity) }
            
            // 3. Delete Vacation Days
            let vacations = try modelContext.fetch(FetchDescriptor<VacationDay>())
            for vacation in vacations { modelContext.delete(vacation) }

            // 4. Delete Categories (EXCEPT Base Defaults)
            let categories = try modelContext.fetch(FetchDescriptor<Category>())
            let defaultNames = Category.defaults.map { $0.name }
            for category in categories {
                if !defaultNames.contains(category.name) {
                    modelContext.delete(category)
                }
            }
            
            // 5. Ensure defaults exist (in case user deleted them previously or they are missing)
            // If we kept them, good. If we deleted them because names matched but we want to reset?
            // Actually, user invoked "Clear Data", usually implies "Reset to Factory".
            // So we should probably keep defaults if they exist, or re-create them if they don't.
            // The logic above keeps them if they exist.
            
            try modelContext.save()
            alertMessage = "All data cleared (Base categories preserved)."
            showAlert = true
        } catch {
            alertMessage = "Failed to clear data: \(error.localizedDescription)"
            showAlert = true
        }
    }

    // MARK: - Reminder Helpers

    @ViewBuilder
    private func reminderRow(
        label: String, icon: String, color: Color,
        enabled: Binding<Bool>, time: Binding<Date>
    ) -> some View {
        VStack(spacing: 4) {
            Toggle(isOn: enabled) {
                Label(label, systemImage: icon)
                    .foregroundStyle(color)
            }
            .onChange(of: enabled.wrappedValue) { _, _ in saveNotificationSettings() }

            if enabled.wrappedValue {
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .onChange(of: time.wrappedValue) { _, _ in saveNotificationSettings() }
            }
        }
    }

    private func saveNotificationSettings() {
        let cal = Calendar.current

        let mc = cal.dateComponents([.hour, .minute], from: morningTime)
        NotificationService.shared.morningConfig = .init(
            enabled: morningEnabled, hour: mc.hour ?? 8, minute: mc.minute ?? 0
        )

        let ac = cal.dateComponents([.hour, .minute], from: afternoonTime)
        NotificationService.shared.afternoonConfig = .init(
            enabled: afternoonEnabled, hour: ac.hour ?? 13, minute: ac.minute ?? 0
        )

        let ec = cal.dateComponents([.hour, .minute], from: eveningTime)
        NotificationService.shared.eveningConfig = .init(
            enabled: eveningEnabled, hour: ec.hour ?? 20, minute: ec.minute ?? 0
        )

        NotificationService.shared.rescheduleAll()
    }
}

// MARK: - Category Management

extension SettingsView {

    private var categoriesSection: some View {
        Section {
            ForEach(categories) { category in
                categoryRow(category)
            }
            .onDelete(perform: deleteCategories)

            Button {
                newCategoryName = ""
                newCategoryIcon = "folder"
                newCategoryColor = "#007AFF"
                showAddCategory = true
            } label: {
                Label("Add Category", systemImage: "plus.circle")
            }

            Button {
                restoreDefaultCategories()
            } label: {
                Label("Restore Defaults", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("Categories")
        } footer: {
            Text("Categories organise your activities into groups. Restore defaults re-creates any missing ones.")
        }
        .alert("Add Category", isPresented: $showAddCategory) {
            TextField("Name", text: $newCategoryName)
            Button("Add") { addCategory() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Category", isPresented: Binding(
            get: { editingCategory != nil },
            set: { if !$0 { editingCategory = nil } }
        )) {
            TextField("Name", text: Binding(
                get: { editingCategory?.name ?? "" },
                set: { editingCategory?.name = $0 }
            ))
            Button("Save") { editingCategory = nil }
            Button("Cancel", role: .cancel) { editingCategory = nil }
        }
    }

    @ViewBuilder
    private func categoryRow(_ category: Category) -> some View {
        HStack(spacing: 10) {
            Image(systemName: category.icon)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: category.hexColor))
                .frame(width: 24)

            Text(category.name)
                .font(.body)

            Spacer()

            // Show badge if it's a default category
            if Category.defaults.contains(where: { $0.name == category.name }) {
                Text("Default")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingCategory = category
        }
    }

    private func deleteCategories(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(categories[index])
        }
    }

    private func addCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let nextSort = (categories.map(\.sortOrder).max() ?? 0) + 1
        let category = Category(name: trimmed, icon: newCategoryIcon, hexColor: newCategoryColor, sortOrder: nextSort)
        modelContext.insert(category)
    }

    private func restoreDefaultCategories() {
        let existingNames = Set(categories.map(\.name))
        var restored = 0
        for (i, def) in Category.defaults.enumerated() {
            if !existingNames.contains(def.name) {
                let cat = Category(name: def.name, icon: def.icon, hexColor: def.color, sortOrder: 1000 + i)
                modelContext.insert(cat)
                restored += 1
            }
        }
        alertMessage = restored > 0 ? "Restored \(restored) default category(ies)." : "All defaults already exist."
        showAlert = true
    }
}

// MARK: - Share Sheet Helper
struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
