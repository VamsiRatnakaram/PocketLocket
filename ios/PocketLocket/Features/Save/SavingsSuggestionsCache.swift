import Foundation

/// Caches the Save tab's suggestions.
///
/// `SavingsAdvisor` input building is the expensive part of that tab: it walks
/// two months of transactions and calls `resolvedCategory(using:)` and
/// `isLikelySubscription` on every row. That was happening inside a computed
/// property read several times per render — and `SuggestionsView` re-renders on
/// every keystroke in the "Ask PocketLocket" field, so typing a question
/// recategorized the whole month once per character.
///
/// Shared (rather than `@State` on the view) so the result also survives the
/// Analysis/Save segmented switch, which tears the view down entirely. That
/// mirrors `AnalysisSnapshotCoordinator.shared`, which is why flipping to
/// Analysis and back is already cheap in that direction.
///
/// Deliberately *not* `@Observable`: reads happen during `body`, and publishing
/// a change from there would invalidate the view that just read it.
@MainActor
final class SavingsSuggestionsCache {
    static let shared = SavingsSuggestionsCache()

    struct InputsKey: Equatable {
        var dataHash: Int
        var rulesHash: Int
        var excludedAccountsRaw: String
        var monthlyBudget: Double
        /// The month the suggestions describe. Without it, leaving the app open
        /// across a month boundary would keep serving last month's advice.
        var monthStart: Date?
    }

    private var key: InputsKey?
    private var cached: [SavingsSuggestion] = []

    /// Number of times `compute` actually ran. Test-only visibility into
    /// whether the cache is doing its job.
    private(set) var missCount = 0

    func suggestions(for key: InputsKey, compute: () -> [SavingsSuggestion]) -> [SavingsSuggestion] {
        if self.key == key { return cached }
        let value = compute()
        self.key = key
        cached = value
        missCount += 1
        return value
    }

    func reset() {
        key = nil
        cached = []
        missCount = 0
    }
}
