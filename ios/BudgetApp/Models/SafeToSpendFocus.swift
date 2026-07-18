import Foundation

/// The categories that "Safe to spend" is based on. When one or more categories
/// are starred (and have a monthly limit), the daily figure reflects those
/// categories' remaining allowance instead of the overall budget. Stored as a
/// comma-separated list of category raw values, observed via `@AppStorage`.
enum SafeToSpendFocus {
    static let key = "safeToSpendFocus"

    static func categories(from raw: String) -> Set<SpendCategory> {
        Set(raw.split(separator: ",").compactMap { SpendCategory(rawValue: String($0)) })
    }

    static func toggling(_ category: SpendCategory, in raw: String) -> String {
        var set = categories(from: raw)
        if set.contains(category) { set.remove(category) } else { set.insert(category) }
        return set.map(\.rawValue).sorted().joined(separator: ",")
    }
}
