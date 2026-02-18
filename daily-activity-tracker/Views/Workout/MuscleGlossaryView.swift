import SwiftUI
import SwiftData

/// Hierarchical muscle glossary with volume benchmarks (MEV/MAV/MRV).
struct MuscleGlossaryView: View {
    @Query(sort: \MuscleGroup.sortOrder) private var muscles: [MuscleGroup]

    private var parentMuscles: [MuscleGroup] {
        muscles.filter { $0.isParent }
    }

    private func children(of parent: MuscleGroup) -> [MuscleGroup] {
        muscles.filter { $0.parentID == parent.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            Section {
                Text("Volume benchmarks per muscle group (sets/week)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)

            ForEach(parentMuscles) { parent in
                Section {
                    // Parent row with benchmarks
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(parent.name)
                                .font(.headline)
                            Spacer()
                        }

                        // Volume benchmark bar
                        HStack(spacing: 12) {
                            benchmarkPill("MEV", value: parent.mevSets, color: .red)
                            benchmarkPill("MAV", value: parent.mavSets, color: .green)
                            benchmarkPill("MRV", value: parent.mrvSets, color: .orange)
                        }

                        // Volume range visualization
                        volumeBar(mev: parent.mevSets, mav: parent.mavSets, mrv: parent.mrvSets)
                    }
                    .padding(.vertical, 4)

                    // Sub-groups
                    let kids = children(of: parent)
                    if !kids.isEmpty {
                        ForEach(kids) { child in
                            HStack {
                                Text("  ├─ \(child.name)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Muscle Glossary")
    }

    private func benchmarkPill(_ label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
            Text("\(value)")
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func volumeBar(mev: Int, mav: Int, mrv: Int) -> some View {
        let maxVal = Double(mrv + 5) // Give breathing room

        GeometryReader { geo in
            let width = geo.size.width

            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray6))

                // Below MEV zone (red)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.red.opacity(0.15))
                    .frame(width: width * (Double(mev) / maxVal))

                // MAV zone (green) — overlaid
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.green.opacity(0.2))
                    .frame(width: width * (Double(mav) / maxVal))
                    .offset(x: width * (Double(mev) / maxVal))
                    .frame(width: width * (Double(mav - mev) / maxVal))

                // Above MRV (orange)
                Rectangle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: width * (1 - Double(mrv) / maxVal))
                    .offset(x: width * (Double(mrv) / maxVal))

                // Markers
                marker(at: Double(mev) / maxVal, width: width, label: "\(mev)", color: .red)
                marker(at: Double(mav) / maxVal, width: width, label: "\(mav)", color: .green)
                marker(at: Double(mrv) / maxVal, width: width, label: "\(mrv)", color: .orange)
            }
        }
        .frame(height: 20)
    }

    private func marker(at fraction: Double, width: CGFloat, label: String, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: 2, height: 20)
            .offset(x: width * fraction)
    }
}
