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

    /// Full-form aliases for each abbreviation so typing "feet" finds "ft"
    private static let aliases: [String: [String]] = [
        "kg": ["kilogram", "kilograms", "kilo", "kilos"],
        "g": ["gram", "grams"],
        "lb": ["pound", "pounds", "lbs"],
        "oz": ["ounce", "ounces"],
        "ml": ["milliliter", "milliliters", "millilitre"],
        "L": ["liter", "liters", "litre", "litres"],
        "fl oz": ["fluid ounce", "fluid ounces"],
        "cups": ["cup"],
        "gal": ["gallon", "gallons"],
        "km": ["kilometer", "kilometers", "kilometre"],
        "mi": ["mile", "miles"],
        "m": ["meter", "meters", "metre", "metres"],
        "ft": ["foot", "feet"],
        "yd": ["yard", "yards"],
        "sec": ["second", "seconds"],
        "min": ["minute", "minutes"],
        "hrs": ["hour", "hours", "hr"],
        "cal": ["calorie", "calories"],
        "kcal": ["kilocalorie", "kilocalories"],
        "bpm": ["beats per minute", "heartrate", "heart rate"],
        "rpm": ["revolutions per minute"],
        "mg": ["milligram", "milligrams"],
        "mcg": ["microgram", "micrograms"],
        "IU": ["international units"],
        "pages": ["page"],
        "reps": ["rep", "repetition", "repetitions"],
        "sets": ["set"],
        "steps": ["step"],
        "doses": ["dose"],
    ]

    private static var allUnits: [String] {
        units.flatMap(\.items)
    }

    private var filteredUnits: [String] {
        guard !selection.isEmpty else { return Self.allUnits }
        let query = selection.lowercased()
        return Self.allUnits.filter { unit in
            // Match the abbreviation itself
            if unit.localizedCaseInsensitiveContains(selection) { return true }
            // Match any full-form alias
            if let unitAliases = Self.aliases[unit] {
                return unitAliases.contains { $0.localizedCaseInsensitiveContains(query) }
            }
            return false
        }
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
