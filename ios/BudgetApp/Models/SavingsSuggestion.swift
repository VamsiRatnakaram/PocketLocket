import SwiftUI

/// A single money-saving idea shown on the Save tab.
struct SavingsSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let monthlyImpact: Double?
    let symbol: String
    let tint: Color
}
