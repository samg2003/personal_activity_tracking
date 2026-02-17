import Foundation
import UniformTypeIdentifiers
import CoreTransferable

/// Custom UTType for dragging activities between containers.
/// Using a custom type prevents text fields from accepting the drop.
extension UTType {
    static let activityTransfer = UTType(exportedAs: "com.dailytracker.activity-transfer")
}

/// Lightweight transferable struct carrying just the activity's UUID.
struct ActivityTransfer: Codable, Transferable {
    let activityId: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .activityTransfer)
    }
}
