import Foundation

/// Per-category monthly budget limits, stored as a JSON `[categoryRawValue: limit]`
/// string in UserDefaults (observed via `@AppStorage`). Optional and supplementary
/// to the overall monthly budget.
enum CategoryBudgetStore {
    static let key = "categoryBudgets"

    static func decode(_ raw: String) -> [SpendCategory: Double] {
        guard
            let data = raw.data(using: .utf8),
            let dict = try? JSONDecoder().decode([String: Double].self, from: data)
        else { return [:] }
        var out: [SpendCategory: Double] = [:]
        for (rawKey, value) in dict where value > 0 {
            if let category = SpendCategory(rawValue: rawKey) { out[category] = value }
        }
        return out
    }

    static func encode(_ budgets: [SpendCategory: Double]) -> String {
        let dict = Dictionary(uniqueKeysWithValues:
            budgets.filter { $0.value > 0 }.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(dict) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
