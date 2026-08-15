import Foundation

/// Controls which accounts feed the spending ring, insights, and drill-downs.
/// Stored as a comma-separated list of *excluded* account ids in UserDefaults,
/// observed via `@AppStorage` so toggling on the Accounts page instantly updates
/// every spending view. Accounts are included by default.
enum SpendingAccountFilter {
    static let key = "excludedAccountIds"

    static func excludedIds(from raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map(String.init))
    }

    static func isIncluded(_ accountId: String?, excluded: Set<String>) -> Bool {
        guard let accountId else { return true }
        return !excluded.contains(accountId)
    }

    /// The single definition of "counts toward the budget", shared by the ring,
    /// the drill-downs, and the Transactions "In budget" filter. All three used
    /// to test slightly different things, so the same transaction could be
    /// listed as in-budget while contributing nothing to the ring.
    static func countsTowardBudget(
        category: SpendCategory,
        amount: Double,
        accountId: String?,
        excluded: Set<String>
    ) -> Bool {
        category.isSpending && amount > 0 && isIncluded(accountId, excluded: excluded)
    }

    /// Returns the raw string with `accountId`'s inclusion flipped.
    static func toggling(_ accountId: String, in raw: String) -> String {
        var set = excludedIds(from: raw)
        if set.contains(accountId) { set.remove(accountId) } else { set.insert(accountId) }
        return set.sorted().joined(separator: ",")
    }
}

extension DateInterval {
    /// Half-open membership. `DateInterval.contains` includes `end`, so a
    /// transaction stamped exactly at the next period's start was counted in
    /// both periods on Home — and disagreed with the SwiftData predicates
    /// behind the drill-downs, which correctly use `date < end`.
    func containsHalfOpen(_ date: Date) -> Bool {
        date >= start && date < end
    }
}
