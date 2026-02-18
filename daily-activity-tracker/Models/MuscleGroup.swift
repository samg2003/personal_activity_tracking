import Foundation
import SwiftData

@Model
final class MuscleGroup {
    var id: UUID = UUID()
    var name: String = ""
    var parentID: UUID?
    var sortOrder: Int = 0
    var mevSets: Int = 0     // Minimum Effective Volume (sets/week)
    var mavSets: Int = 0     // Maximum Adaptive Volume
    var mrvSets: Int = 0     // Maximum Recoverable Volume
    var isPreSeeded: Bool = false

    // MARK: - Computed

    /// Whether this is a top-level muscle group (not a sub-group)
    var isParent: Bool { parentID == nil }

    // MARK: - Init

    init(
        name: String,
        parentID: UUID? = nil,
        sortOrder: Int = 0,
        mevSets: Int = 0,
        mavSets: Int = 0,
        mrvSets: Int = 0,
        isPreSeeded: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.parentID = parentID
        self.sortOrder = sortOrder
        self.mevSets = mevSets
        self.mavSets = mavSets
        self.mrvSets = mrvSets
        self.isPreSeeded = isPreSeeded
    }
}

// MARK: - Pre-seed Data

extension MuscleGroup {

    /// Builds the full muscle hierarchy. Returns (parents, all) where `all` includes children.
    static func buildGlossary() -> [MuscleGroup] {
        var all: [MuscleGroup] = []
        var order = 0

        func parent(_ name: String, mev: Int, mav: Int, mrv: Int, children: [String]) -> MuscleGroup {
            let p = MuscleGroup(name: name, sortOrder: order, mevSets: mev, mavSets: mav, mrvSets: mrv, isPreSeeded: true)
            order += 1
            all.append(p)
            for child in children {
                let c = MuscleGroup(name: child, parentID: p.id, sortOrder: order, isPreSeeded: true)
                order += 1
                all.append(c)
            }
            return p
        }

        _ = parent("Chest", mev: 8, mav: 16, mrv: 22, children: ["Upper Chest", "Lower Chest"])
        _ = parent("Back", mev: 8, mav: 16, mrv: 22, children: ["Lats", "Upper Back / Traps", "Rhomboids", "Lower Back / Erectors"])
        _ = parent("Shoulders", mev: 6, mav: 14, mrv: 20, children: ["Front Delts", "Side Delts", "Rear Delts"])
        _ = parent("Triceps", mev: 6, mav: 12, mrv: 18, children: ["Long Head", "Lateral Head", "Medial Head"])
        _ = parent("Biceps", mev: 6, mav: 14, mrv: 20, children: [])
        _ = parent("Forearms", mev: 4, mav: 10, mrv: 16, children: ["Extensors", "Flexors"])
        _ = parent("Quads", mev: 8, mav: 16, mrv: 22, children: ["Vastus Lateralis", "Vastus Medialis", "Rectus Femoris"])
        _ = parent("Hamstrings", mev: 6, mav: 12, mrv: 18, children: [])
        _ = parent("Glutes", mev: 6, mav: 14, mrv: 20, children: ["Glute Max", "Glute Med"])
        _ = parent("Calves", mev: 8, mav: 14, mrv: 20, children: ["Gastrocnemius", "Soleus"])
        _ = parent("Core", mev: 6, mav: 12, mrv: 18, children: ["Upper Abs", "Lower Abs", "Obliques", "Transverse Abdominis"])

        return all
    }
}
