import SwiftUI
import SwiftData

/// Sheet showing all log entries for a cumulative activity on a specific day.
/// Supports swipe-left to stage deletions, with a single confirmation on save.
struct CumulativeLogSheet: View {
    let activity: Activity
    let date: Date
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ActivityLog.date, order: .reverse) private var allLogs: [ActivityLog]
    
    @State private var pendingDeletions: Set<UUID> = []
    @State private var showConfirmation = false
    
    private var dayLogs: [ActivityLog] {
        allLogs.filter { log in
            log.activity?.id == activity.id &&
            log.date.isSameDay(as: date) &&
            log.status == .completed
        }
    }
    
    /// Logs that will remain after staged deletions are applied
    private var visibleLogs: [ActivityLog] {
        dayLogs.filter { !pendingDeletions.contains($0.id) }
    }
    
    private var currentTotal: Double {
        visibleLogs.reduce(0) { $0 + ($1.value ?? 0) }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Total")
                            .font(.headline)
                        Spacer()
                        Text("\(formatValue(currentTotal)) \(activity.unit ?? "")")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(Color(hex: activity.hexColor))
                    }
                    
                    if let target = activity.targetValue {
                        ProgressView(value: min(currentTotal / target, 1.0))
                            .tint(Color(hex: activity.hexColor))
                    }
                }
                
                Section("Entries") {
                    if visibleLogs.isEmpty {
                        Text("No entries")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(visibleLogs) { log in
                            HStack {
                                Text(log.date, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("+\(formatValue(log.value ?? 0)) \(activity.unit ?? "")")
                                    .font(.system(.body, design: .rounded, weight: .medium))
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                pendingDeletions.insert(visibleLogs[index].id)
                            }
                        }
                    }
                }
                
                if !pendingDeletions.isEmpty {
                    Section {
                        Text("\(pendingDeletions.count) entries staged for removal")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(activity.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if pendingDeletions.isEmpty {
                            dismiss()
                        } else {
                            showConfirmation = true
                        }
                    }
                    .bold()
                    .disabled(pendingDeletions.isEmpty)
                }
            }
            .confirmationDialog(
                "Remove \(pendingDeletions.count) entries?",
                isPresented: $showConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    applyDeletions()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
    
    private func applyDeletions() {
        let logsToDelete = dayLogs.filter { pendingDeletions.contains($0.id) }
        for log in logsToDelete {
            modelContext.delete(log)
        }
    }
    
    private func formatValue(_ val: Double) -> String {
        val.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", val)
            : String(format: "%.1f", val)
    }
}
