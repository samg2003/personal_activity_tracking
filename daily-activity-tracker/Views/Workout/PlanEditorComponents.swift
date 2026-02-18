import SwiftUI
import SwiftData

/// Shared UI components used by both Strength and Cardio plan editors.
enum PlanEditorComponents {

    // MARK: - Week Strip

    /// Horizontal row of 7 tappable day pills. Long-press cycles color group.
    struct WeekStrip: View {
        let days: [WorkoutPlanDay]
        @Binding var selectedIndex: Int
        var accentColor: Color = .orange
        let modelContext: ModelContext

        var body: some View {
            HStack(spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    DayPill(
                        day: day,
                        isSelected: index == selectedIndex,
                        accentColor: accentColor,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedIndex = index
                            }
                        },
                        onLongPress: {
                            cycleColor(day)
                        }
                    )
                }
            }
        }

        private func cycleColor(_ day: WorkoutPlanDay) {
            let next = (day.colorGroup + 2) % 8 - 1  // -1..6 cycle
            day.colorGroup = next
            try? modelContext.save()
        }
    }

    /// Single day pill in the week strip.
    /// - Tap: selects this day in the detail view
    /// - Long-press: cycles the color group for day linking
    /// - Selected: hollow outline with the day's link color (or accent)
    /// - Non-selected linked: filled background tint
    struct DayPill: View {
        let day: WorkoutPlanDay
        let isSelected: Bool
        var accentColor: Color = .orange
        let onTap: () -> Void
        var onLongPress: (() -> Void)? = nil

        private var dayColor: Color {
            guard day.isLinked, day.colorGroup >= 0, day.colorGroup < WorkoutPlanDay.linkColors.count else {
                return accentColor
            }
            return Self.linkColor(day.colorGroup)
        }

        var body: some View {
            VStack(spacing: 2) {
                Text(day.weekdayName)
                    .font(.system(size: 11, weight: .semibold))

                if day.isRest {
                    Text("Rest")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                } else {
                    if !day.dayLabel.isEmpty {
                        Text(day.dayLabel)
                            .font(.system(size: 9))
                            .lineLimit(1)
                    }
                    let count = day.totalSets > 0 ? "\(day.totalSets)s" :
                               !day.cardioExercises.isEmpty ? "\(day.cardioExercises.count)ex" : nil
                    if let count {
                        Text(count)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.clear : pillFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? dayColor : .clear, lineWidth: 2)
            )
            .onTapGesture(perform: onTap)
            .onLongPressGesture {
                onLongPress?()
            }
        }

        /// Non-selected: linked days get a tinted fill, unlinked get gray.
        private var pillFill: Color {
            guard day.isLinked else { return Color(.systemGray6) }
            return dayColor.opacity(0.12)
        }

        static func linkColor(_ group: Int) -> Color {
            switch group {
            case 0: return .red
            case 1: return .orange
            case 2: return .yellow
            case 3: return .green
            case 4: return .blue
            case 5: return .purple
            case 6: return .gray
            default: return .gray
            }
        }
    }

    // MARK: - Swipable Day Container

    /// Container that renders a single day's content with swipe-to-navigate gesture.
    struct SwipableDayContainer<Content: View>: View {
        @Binding var selectedIndex: Int
        let dayCount: Int
        @ViewBuilder var content: () -> Content

        var body: some View {
            Group {
                content()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
                    .id(selectedIndex)
            }
            .gesture(
                DragGesture(minimumDistance: 50)
                    .onEnded { value in
                        let horizontal = value.translation.width
                        guard abs(horizontal) > abs(value.translation.height) else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if horizontal < 0, selectedIndex < dayCount - 1 {
                                selectedIndex += 1
                            } else if horizontal > 0, selectedIndex > 0 {
                                selectedIndex -= 1
                            }
                        }
                    }
            )
        }
    }

    // MARK: - Plan Header

    struct PlanHeader: View {
        let plan: WorkoutPlan
        let icon: String
        var accentColor: Color = .orange

        var body: some View {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(accentColor)
                Text(plan.name)
                    .font(.headline)
                Spacer()
                StatusBadge(plan: plan, accentColor: accentColor)
            }
        }
    }

    struct StatusBadge: View {
        let plan: WorkoutPlan
        var accentColor: Color = .orange

        var body: some View {
            HStack(spacing: 4) {
                Image(systemName: plan.status.icon)
                    .font(.caption2)
                Text(plan.status.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(plan.isActive ? accentColor.opacity(0.15) : Color(.systemGray5))
            .foregroundStyle(plan.isActive ? accentColor : .secondary)
            .clipShape(Capsule())
        }
    }

    // MARK: - Day Editor Header

    struct DayEditorHeader: View {
        let day: WorkoutPlanDay
        let subtitle: String?
        let onToggleRest: () -> Void

        var body: some View {
            HStack {
                Text(day.weekdayFullName)
                    .font(.title3.weight(.semibold))

                if let subtitle {
                    Text("· \(subtitle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onToggleRest) {
                    Text(day.isRest ? "Train" : "Rest")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Day Label Row

    struct DayLabelRow: View {
        let day: WorkoutPlanDay
        var accentColor: Color = .orange
        let onEdit: () -> Void

        var body: some View {
            HStack {
                if !day.dayLabel.isEmpty {
                    Text(day.dayLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(accentColor)
                } else {
                    Text("No label")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Rest Day Content

    struct RestDayView: View {
        var body: some View {
            HStack {
                Image(systemName: "bed.double.fill")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("Rest Day")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Add Exercise Button

    struct AddExerciseButton: View {
        var accentColor: Color = .orange
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Exercise")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Activate / Deactivate

    struct ActivateButton: View {
        let plan: WorkoutPlan
        var accentColor: Color = .orange
        let onActivate: () -> Void
        let onDeactivate: () -> Void

        var body: some View {
            if plan.isDraft {
                Button(action: onActivate) {
                    Text("Activate Plan")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else if plan.isActive {
                Button(role: .destructive, action: onDeactivate) {
                    Text("Deactivate Plan")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - Rename Alert Modifier

    struct RenameDayModifier: ViewModifier {
        @Binding var isPresented: Bool
        @Binding var labelText: String
        let day: WorkoutPlanDay?
        let modelContext: ModelContext
        let planManager: WorkoutPlanManager

        func body(content: Content) -> some View {
            content
                .alert("Rename Day", isPresented: $isPresented) {
                    TextField("Label", text: $labelText)
                    Button("Save") {
                        if let day {
                            day.dayLabel = labelText
                            day.isLabelOverridden = true
                            try? modelContext.save()
                        }
                    }
                    Button("Reset to Auto") {
                        if let day {
                            day.isLabelOverridden = false
                            day.dayLabel = planManager.autoDetectDayLabel(for: day)
                            try? modelContext.save()
                        }
                    }
                    Button("Cancel", role: .cancel) { }
                }
        }
    }
}

extension View {
    func renameDayAlert(
        isPresented: Binding<Bool>,
        labelText: Binding<String>,
        day: WorkoutPlanDay?,
        modelContext: ModelContext,
        planManager: WorkoutPlanManager
    ) -> some View {
        modifier(PlanEditorComponents.RenameDayModifier(
            isPresented: isPresented,
            labelText: labelText,
            day: day,
            modelContext: modelContext,
            planManager: planManager
        ))
    }
}
