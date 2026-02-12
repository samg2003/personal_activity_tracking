import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "folder"
    var hexColor: String = "#007AFF"
    var sortOrder: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \Activity.category)
    var activities: [Activity] = []

    init(name: String, icon: String, hexColor: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.hexColor = hexColor
        self.sortOrder = sortOrder
    }
}

extension Category {
    static let defaults: [(name: String, icon: String, color: String)] = [
        ("Workout", "figure.run", "#FF6B35"),
        ("Supplement", "pills.fill", "#4ECDC4"),
        ("Hygiene", "drop.fill", "#45B7D1"),
        ("Medical", "cross.case.fill", "#FF6B6B"),
        ("Skills", "brain", "#C44DFF"),
        ("Tracking", "chart.line.uptrend.xyaxis", "#96CEB4"),
    ]
}
