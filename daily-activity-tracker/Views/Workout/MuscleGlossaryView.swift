import SwiftUI
import SwiftData

/// Hierarchical muscle glossary with volume benchmarks (MEV/MAV/MRV) — premium styled.
struct MuscleGlossaryView: View {
    @Query(sort: \MuscleGroup.sortOrder) private var muscles: [MuscleGroup]

    private var parentMuscles: [MuscleGroup] {
        muscles.filter { $0.isParent }
    }

    private func children(of parent: MuscleGroup) -> [MuscleGroup] {
        muscles.filter { $0.parentID == parent.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Info banner
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(WDS.infoAccent)
                    Text("Volume benchmarks per muscle group (sets/week)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WDS.infoAccent.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal)

                // Muscle groups
                LazyVStack(spacing: 10) {
                    ForEach(parentMuscles) { parent in
                        muscleGroupCard(parent)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Muscle Glossary")
    }

    // MARK: - Muscle Group Card

    private func muscleGroupCard(_ parent: MuscleGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                IconBadge(icon: "figure.strengthtraining.traditional", color: WDS.strengthAccent, size: 32)
                Text(parent.name)
                    .font(.headline)
                Spacer()
            }

            // Benchmark pills
            HStack(spacing: 8) {
                benchmarkPill("MEV", value: parent.mevSets, color: WDS.dangerAccent)
                benchmarkPill("MAV", value: parent.mavSets, color: WDS.cardioAccent)
                benchmarkPill("MRV", value: parent.mrvSets, color: WDS.strengthAccent)
            }

            // Volume bar
            volumeBar(mev: parent.mevSets, mav: parent.mavSets, mrv: parent.mrvSets)

            // Sub-groups
            let kids = children(of: parent)
            if !kids.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(kids) { child in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(WDS.strengthAccent.opacity(0.3))
                                .frame(width: 5, height: 5)
                            Text(child.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 8)
            }
        }
        .premiumCard(accent: WDS.strengthAccent)
    }

    // MARK: - Components

    private func benchmarkPill(_ label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
            Text("\(value)")
                .font(.caption.monospacedDigit().weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func volumeBar(mev: Int, mav: Int, mrv: Int) -> some View {
        let maxVal = Double(mrv + 5)

        GeometryReader { geo in
            let width = geo.size.width

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))

                // MEV zone
                RoundedRectangle(cornerRadius: 4)
                    .fill(WDS.dangerAccent.opacity(0.15))
                    .frame(width: width * (Double(mev) / maxVal))

                // MAV zone
                RoundedRectangle(cornerRadius: 4)
                    .fill(WDS.cardioAccent.opacity(0.2))
                    .frame(width: width * (Double(mav - mev) / maxVal))
                    .offset(x: width * (Double(mev) / maxVal))

                // Above MRV
                Rectangle()
                    .fill(WDS.strengthAccent.opacity(0.15))
                    .frame(width: width * (1 - Double(mrv) / maxVal))
                    .offset(x: width * (Double(mrv) / maxVal))

                // Markers
                marker(at: Double(mev) / maxVal, width: width, color: WDS.dangerAccent)
                marker(at: Double(mav) / maxVal, width: width, color: WDS.cardioAccent)
                marker(at: Double(mrv) / maxVal, width: width, color: WDS.strengthAccent)
            }
        }
        .frame(height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func marker(at fraction: Double, width: CGFloat, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: 2, height: 20)
            .offset(x: width * fraction)
    }
}
