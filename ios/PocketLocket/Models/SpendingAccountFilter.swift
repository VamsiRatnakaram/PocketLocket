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

    /// Returns the raw string with `accountId`'s inclusion flipped.
    static func toggling(_ accountId: String, in raw: String) -> String {
        var set = excludedIds(from: raw)
        if set.contains(accountId) { set.remove(accountId) } else { set.insert(accountId) }
        return set.sorted().joined(separator: ",")
    }
}
