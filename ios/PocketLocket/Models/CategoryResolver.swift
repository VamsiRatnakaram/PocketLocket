import Foundation
import SwiftData

/// A `CategoryRule` reduced to plain values.
///
/// `CategoryRule` is a SwiftData `@Model` and therefore bound to its
/// `ModelContext` — it can't be handed to a background executor. Extract these
/// on the main thread instead and pass them across.
struct CategoryRuleSpec: Sendable, Hashable {
    let matchText: String
    let category: SpendCategory

    init(matchText: String, category: SpendCategory) {
        self.matchText = matchText
        self.category = category
    }

    init(rule: CategoryRule) {
        self.init(matchText: rule.matchText, category: rule.category)
    }
}

struct CategoryRuleIndex {
    private struct Entry {
        let tokens: [String]
        let category: SpendCategory
    }

    private let entries: [Entry]

    init(rules: [CategoryRule]) {
        self.init(specs: rules.map(CategoryRuleSpec.init(rule:)))
    }

    init(specs: [CategoryRuleSpec]) {
        entries = specs.map {
            Entry(tokens: MerchantHeuristics.tokens(in: $0.matchText), category: $0.category)
        }
    }

    func category(for descriptor: String) -> SpendCategory? {
        let descriptorTokens = MerchantHeuristics.tokens(in: descriptor)
        return entries.first {
            MerchantHeuristics.contains($0.tokens, in: descriptorTokens)
        }?.category
    }
}

/// Resolves a transaction's category with a clear priority order:
///   1. User rules (taught by recategorizing a transaction)
///   2. A recognized category provided by the source institution
///   3. Built-in merchant heuristics
///
/// Pure and side-effect free so it is easy to unit test.
enum CategoryResolver {
    private final class RuleIndexBox: NSObject {
        let index: CategoryRuleIndex
        init(_ index: CategoryRuleIndex) { self.index = index }
    }

    private static let ruleIndexCache: NSCache<NSString, RuleIndexBox> = {
        let cache = NSCache<NSString, RuleIndexBox>()
        cache.countLimit = 8
        return cache
    }()

    static func resolve(
        name: String,
        merchant: String?,
        plaidPrimary: String?,
        rules: [CategoryRule]
    ) -> SpendCategory {
        resolve(name: name, merchant: merchant, plaidPrimary: plaidPrimary, index: ruleIndex(for: rules))
    }

    /// Same resolution, but against a pre-built rule index instead of live
    /// SwiftData models — usable off the main thread (see `CategoryRuleSpec`).
    static func resolve(
        name: String,
        merchant: String?,
        plaidPrimary: String?,
        index: CategoryRuleIndex
    ) -> SpendCategory {
        let haystack = ((merchant ?? "") + " " + name).lowercased()

        if let ruleCategory = index.category(for: haystack) {
            return ruleCategory
        }
        if let providerCategory = CategoryMapper.recognizedCategory(primary: plaidPrimary) {
            return providerCategory
        }
        if let heuristic = MerchantHeuristics.category(for: haystack) {
            return heuristic
        }
        return CategoryMapper.map(primary: plaidPrimary)
    }

    private static func ruleIndex(for rules: [CategoryRule]) -> CategoryRuleIndex {
        let signature = rules
            .map { "\($0.matchText)\u{1F}\($0.categoryRaw)" }
            .joined(separator: "\u{1E}") as NSString
        if let cached = ruleIndexCache.object(forKey: signature) {
            return cached.index
        }
        let index = CategoryRuleIndex(rules: rules)
        ruleIndexCache.setObject(RuleIndexBox(index), forKey: signature)
        return index
    }
}

@MainActor
enum CategoryAssignment {
    static func matchKey(for transaction: TransactionRecord) -> String {
        let descriptor = transaction.merchantName ?? transaction.name
        let cleaned = MerchantHeuristics.ruleMatchText(for: descriptor)
        return (cleaned.isEmpty ? descriptor : cleaned).lowercased()
    }

    static func assign(
        _ category: SpendCategory,
        to transactions: [TransactionRecord],
        using rules: [CategoryRule],
        in context: ModelContext
    ) throws {
        var rulesByKey = rules.reduce(into: [String: CategoryRule]()) { result, rule in
            result[rule.matchText] = rule
        }

        for transaction in transactions {
            let key = matchKey(for: transaction)
            if let existing = rulesByKey[key] {
                existing.categoryRaw = category.rawValue
            } else {
                let rule = CategoryRule(matchText: key, category: category)
                context.insert(rule)
                rulesByKey[key] = rule
            }
        }
        try context.save()
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
