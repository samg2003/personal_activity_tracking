import SwiftUI

/// Predefined unit abbreviations grouped by category
struct UnitPicker: View {
    @Binding var selection: String
    @State private var isExpanded = false

    static let units: [(category: String, items: [String])] = [
        ("Weight", ["kg", "g", "lb", "oz"]),
        ("Volume", ["ml", "L", "fl oz", "cups", "gal"]),
        ("Distance", ["km", "mi", "m", "ft", "yd"]),
        ("Time", ["sec", "min", "hrs"]),
        ("Count", ["steps", "reps", "sets", "cal", "kcal", "pages"]),
        ("Rate", ["bpm", "%", "rpm", "°F", "°C"]),
        ("Other", ["units", "doses", "mg", "mcg", "IU"])
    ]

    private static var allUnits: [String] {
        units.flatMap(\.items)
    }

    private var filteredUnits: [String] {
        guard !selection.isEmpty else { return Self.allUnits }
        return Self.allUnits.filter { $0.localizedCaseInsensitiveContains(selection) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Unit (e.g., kg, bpm)", text: $selection)
                .onChange(of: selection) { _, _ in
                    isExpanded = true
                }

            if isExpanded && !filteredUnits.isEmpty && !Self.allUnits.contains(selection) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(filteredUnits, id: \.self) { unit in
                            Button {
                                selection = unit
                                isExpanded = false
                            } label: {
                                Text(unit)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.accentColor.opacity(0.12))
                                    .foregroundStyle(.primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .animation(.easeInOut(duration: 0.2), value: filteredUnits.count)
    }
}
