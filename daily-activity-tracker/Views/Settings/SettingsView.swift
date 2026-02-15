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
    
    var body: some View {
        NavigationStack {
            List {
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
