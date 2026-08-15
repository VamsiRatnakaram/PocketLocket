import SwiftUI

/// A single money-saving idea shown on the Save tab.
///
/// The stored tint is a small value rather than `Color`, making the suggestion
/// safe to produce on the background actor. `color` is materialized only when
/// SwiftUI renders the card.
struct SavingsSuggestion: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let monthlyImpact: Double?
    let symbol: String
    let tint: AppTint

    init(
        id: String = UUID().uuidString,
        title: String,
        detail: String,
        monthlyImpact: Double?,
        symbol: String,
        tint: AppTint
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.monthlyImpact = monthlyImpact
        self.symbol = symbol
        self.tint = tint
    }

    var color: Color { tint.color }
}
