import SwiftUI
import SwiftData

/// Sheet for managing vacation days — toggle today or selected date, add/remove date ranges
struct VacationModeSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \VacationDay.date, order: .reverse) private var vacationDays: [VacationDay]

    /// The date the user is currently viewing on the dashboard
    var selectedDate: Date = Date()

    @State private var addDate = Date()
    @State private var endDate = Date()
    @State private var showDatePicker = false

    private var todayIsVacation: Bool {
        vacationDays.contains { $0.date.isSameDay(as: Date()) }
    }
    
    private var selectedIsVacation: Bool {
        vacationDays.contains { $0.date.isSameDay(as: selectedDate) }
    }
    
    private var showSelectedToggle: Bool {
        !selectedDate.isSameDay(as: Date())
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
                    
                    // Toggle for the selected date (if viewing a different day)
                    if showSelectedToggle {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundStyle(.blue)
                                .font(.title3)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(selectedDate.shortDisplay) is vacation")
                                    .font(.subheadline.bold())
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { selectedIsVacation },
                                set: { isOn in toggleVacation(for: selectedDate, isOn: isOn) }
                            ))
                            .labelsHidden()
                        }
                    }
                }

                // Add future/past vacation
                Section("Add Vacation Range") {
                    DatePicker("Start Date", selection: $addDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $endDate, in: addDate..., displayedComponents: .date)

                    Button {
                        addVacationRange(start: addDate, end: endDate)
                    } label: {
                        Label("Add Vacation", systemImage: "plus.circle.fill")
                    }
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

    private func addVacationRange(start: Date, end: Date) {
        var current = start.startOfDay
        let endDay = end.startOfDay
        
        while current <= endDay {
            if !vacationDays.contains(where: { $0.date.isSameDay(as: current) }) {
                let vacation = VacationDay(date: current)
                modelContext.insert(vacation)
            }
            current = Calendar.current.date(byAdding: .day, value: 1, to: current) ?? current.addingTimeInterval(86400)
        }
        
        // Reset validation or feedback?
        // UI updates automatically via Query
    }
    
    private func addVacationDay(_ date: Date) {
        addVacationRange(start: date, end: date)
    }

    private func deleteVacationDays(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(vacationDays[index])
        }
    }
}
