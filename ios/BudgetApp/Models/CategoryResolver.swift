import Foundation

/// Resolves a transaction's category with a clear priority order:
///   1. User rules (taught by recategorizing a transaction)
///   2. Built-in merchant heuristics
///   3. Plaid `personal_finance_category` mapping
///
/// Pure and side-effect free so it is easy to unit test.
enum CategoryResolver {
    static func resolve(
        name: String,
        merchant: String?,
        plaidPrimary: String?,
        rules: [CategoryRule]
    ) -> SpendCategory {
        let haystack = ((merchant ?? "") + " " + name).lowercased()

        for rule in rules where !rule.matchText.isEmpty && haystack.contains(rule.matchText) {
            return rule.category
        }
        if let heuristic = MerchantHeuristics.category(for: haystack) {
            return heuristic
        }
        return CategoryMapper.map(primary: plaidPrimary)
    }
}

extension TransactionRecord {
    /// The category after applying user rules, heuristics, then Plaid mapping.
    func resolvedCategory(using rules: [CategoryRule]) -> SpendCategory {
        CategoryResolver.resolve(
            name: name,
            merchant: merchantName,
            plaidPrimary: categoryPrimary,
            rules: rules
        )
    }
}
