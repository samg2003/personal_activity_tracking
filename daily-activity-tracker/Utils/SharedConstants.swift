import SwiftUI

/// Centralized skip reasons — used by all row views (ActivityRowView, ContainerRowView, CumulativeRingView, ValueInputRow)
enum SkipReasons {
    static let defaults = ["Injury", "Weather", "Sick", "Not Feeling Well", "Gym Closed", "Other"]
}

/// Shared color for score/rate thresholds — used by Goals and Analytics
func scoreColor(_ score: Double) -> Color {
    if score >= 0.8 { return .green }
    if score >= 0.5 { return .orange }
    return .red
}
