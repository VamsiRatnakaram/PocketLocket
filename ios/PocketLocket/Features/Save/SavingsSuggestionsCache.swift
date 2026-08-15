import Foundation

/// Main-actor memo for completed Save suggestions.
///
/// `SavingsAdvisor` input building is the expensive part of that tab: it walks
/// two months of transactions and calls `resolvedCategory(using:)` and
/// `isLikelySubscription` on every row. That was happening inside a computed
/// property read several times per render — and `SuggestionsView` re-renders on
/// every keystroke in the "Ask PocketLocket" field, so typing a question
/// recategorized the whole month once per character.
///
/// Shared so completed work survives leaving this tab or rebuilding its view
/// hierarchy. Expensive input construction now happens in
/// `SavingsSuggestionsEngine`; this cache only publishes finished values.
///
/// Deliberately *not* `@Observable`: reads happen during `body`, and publishing
/// a change from there would invalidate the view that just read it.
@MainActor
final class SavingsSuggestionsCache {
    static let shared = SavingsSuggestionsCache()

    struct InputsKey: Equatable, Sendable {
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

    /// Number of completed values stored. Test-only visibility into whether
    /// the coordinator is doing duplicate work.
    private(set) var missCount = 0

    func value(for key: InputsKey) -> [SavingsSuggestion]? {
        self.key == key ? cached : nil
    }

    func store(_ suggestions: [SavingsSuggestion], for key: InputsKey) {
        self.key = key
        cached = suggestions
        missCount += 1
    }

    func reset() {
        key = nil
        cached = []
        missCount = 0
    }
}
