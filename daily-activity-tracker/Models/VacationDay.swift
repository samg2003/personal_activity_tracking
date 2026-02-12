import Foundation
import SwiftData

@Model
final class VacationDay {
    var id: UUID = UUID()
    var date: Date = Date()

    init(date: Date) {
        self.id = UUID()
        self.date = date.startOfDay
    }
}
