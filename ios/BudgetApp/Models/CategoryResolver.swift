import Foundation

/// Resolves a transaction's category with a clear priority order:
///   1. User rules (taught by recategorizing a transaction)
///   2. A recognized category provided by the source institution
///   3. Built-in merchant heuristics
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

        for rule in rules {
            if MerchantHeuristics.matches(rule.matchText, in: haystack) {
                return rule.category
            }
        }
        if let providerCategory = CategoryMapper.recognizedCategory(primary: plaidPrimary) {
            return providerCategory
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
