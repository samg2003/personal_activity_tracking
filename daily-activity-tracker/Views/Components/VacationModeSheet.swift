import SwiftUI
import SwiftData

/// Sheet for managing vacation days — toggle today, or add/remove specific dates
struct VacationModeSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \VacationDay.date, order: .reverse) private var vacationDays: [VacationDay]

    @State private var addDate = Date()
    @State private var showDatePicker = false

    private var todayIsVacation: Bool {
        vacationDays.contains { $0.date.isSameDay(as: Date()) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Quick toggle for today
                Section {
                    HStack {
                        Image(systemName: "airplane")
                            .foregroundStyle(.blue)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Today is vacation")
                                .font(.subheadline.bold())
                            Text("Activities won't count against your streak")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { todayIsVacation },
                            set: { isOn in toggleVacation(for: Date(), isOn: isOn) }
                        ))
                        .labelsHidden()
                    }
                }

                // Add future/past vacation
                Section("Add Vacation Day") {
                    DatePicker("Date", selection: $addDate, displayedComponents: .date)

                    Button {
                        addVacationDay(addDate)
                    } label: {
                        Label("Add Day", systemImage: "plus.circle.fill")
                    }
                    .disabled(vacationDays.contains { $0.date.isSameDay(as: addDate) })
                }

                // Existing vacation days
                if !vacationDays.isEmpty {
                    Section("Vacation Days") {
                        ForEach(vacationDays) { day in
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundStyle(.blue)
                                Text(day.date.shortDisplay)
                                    .font(.subheadline)

                                Spacer()

                                if day.date.isSameDay(as: Date()) {
                                    Text("Today")
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.blue.opacity(0.15))
                                        .foregroundStyle(.blue)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .onDelete(perform: deleteVacationDays)
                    }
                }
            }
            .navigationTitle("Vacation Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleVacation(for date: Date, isOn: Bool) {
        if isOn {
            addVacationDay(date)
        } else {
            if let existing = vacationDays.first(where: { $0.date.isSameDay(as: date) }) {
                modelContext.delete(existing)
            }
        }
    }

    private func addVacationDay(_ date: Date) {
        guard !vacationDays.contains(where: { $0.date.isSameDay(as: date) }) else { return }
        let vacation = VacationDay(date: date)
        modelContext.insert(vacation)
    }

    private func deleteVacationDays(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(vacationDays[index])
        }
    }
}
