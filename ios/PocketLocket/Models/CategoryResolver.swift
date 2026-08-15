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
        // A peer-to-peer rail is uninformative whoever says so, including the
        // institution: banks tag these TRANSFER_OUT because of how the money
        // moved, which is why some Zelles landed outside the budget and others
        // inside, depending only on whether the bank bothered to categorize.
        let isPeerToPeer = PeerToPeerPayments.isPlatform(haystack)
        if let providerCategory = CategoryMapper.recognizedCategory(primary: plaidPrimary),
           !(isPeerToPeer && providerCategory == .transfer) {
            return providerCategory
        }
        if let heuristic = MerchantHeuristics.category(for: haystack) {
            return heuristic
        }
        let fallback = CategoryMapper.map(primary: plaidPrimary)
        return isPeerToPeer && fallback == .transfer ? .other : fallback
    }

    /// Whether the user has explicitly taught a category for this descriptor.
    /// Exposed so a caller with stronger evidence (a matched transfer pair) can
    /// still yield to a deliberate user override.
    static func userRuleCategory(name: String, merchant: String?, rules: [CategoryRule]) -> SpendCategory? {
        let haystack = ((merchant ?? "") + " " + name).lowercased()
        return ruleIndex(for: rules).category(for: haystack)
    }

    private static func ruleIndex(for rules: [CategoryRule]) -> CategoryRuleIndex {        let signature = rules
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
    /// How far a category choice should reach.
    enum Scope {
        /// Applies to this transaction alone, leaving every other transaction
        /// from the same merchant untouched.
        case thisTransactionOnly
        /// Teaches a rule so every transaction matching the merchant descriptor
        /// is categorized this way, now and in future syncs.
        case allMatching
    }

    /// The text a taught rule matches on.
    ///
    /// This is deliberately the same merchant identity the Analysis tab groups
    /// by: without it, whether "always categorize" reached the whole merchant
    /// depended on which transaction you happened to tap — tapping
    /// "Safeway #1993" taught `safeway` and caught everything, while tapping
    /// "SAFEWAY 1993 SEATTLE WA" taught the whole descriptor and caught only
    /// itself. Passing the ledger lets store numbers, statement references and
    /// city suffixes fold away, so a utility that renames itself every month
    /// still lands under one rule.
    static func matchKey(for transaction: TransactionRecord, in ledger: [TransactionRecord] = []) -> String {
        let descriptor = transaction.merchantName ?? transaction.name
        let normalized = MerchantNormalizer.normalize(descriptor)
        if !ledger.isEmpty {
            let canonical = MerchantNormalizer.canonicalKeys(
                for: ledger.map { MerchantNormalizer.groupingKey($0.merchantName ?? $0.name) },
                policy: .userAsserted
            )
            if let name = canonical[MerchantNormalizer.groupingKey(descriptor)],
               !isTooBroad(name, among: canonical.values) {
                let cleaned = MerchantHeuristics.ruleMatchText(for: name)
                return (cleaned.isEmpty ? name : cleaned).lowercased()
            }
            // The merchant identity is a prefix of another merchant in the
            // ledger, so a rule keyed on it would silently swallow that one
            // too. Stay with the descriptor, which is specific enough.
            let cleaned = MerchantHeuristics.ruleMatchText(for: descriptor)
            if !cleaned.isEmpty { return cleaned.lowercased() }
        }
        let cleaned = MerchantHeuristics.ruleMatchText(for: normalized)
        return (cleaned.isEmpty ? descriptor : cleaned).lowercased()
    }

    /// Whether a rule keyed on `name` would also match a different merchant
    /// that happens to start with it — "Uber" would catch every "Uber Eats".
    private static func isTooBroad(_ name: String, among names: some Sequence<String>) -> Bool {
        let tokens = MerchantHeuristics.tokens(in: name)
        return names.contains { other in
            let otherTokens = MerchantHeuristics.tokens(in: other)
            return otherTokens.count > tokens.count && otherTokens.starts(with: tokens)
        }
    }

    static func assign(
        _ category: SpendCategory,
        to transactions: [TransactionRecord],
        using rules: [CategoryRule],
        in context: ModelContext,
        scope: Scope = .allMatching,
        ledger: [TransactionRecord] = []
    ) throws {
        guard scope == .allMatching else {
            for transaction in transactions {
                transaction.categoryOverride = category
            }
            try context.save()
            return
        }

        var rulesByKey = rules.reduce(into: [String: CategoryRule]()) { result, rule in
            result[rule.matchText] = rule
        }

        for transaction in transactions {
            // A stale per-transaction override would outrank the rule being
            // taught here, so the choice would appear not to take effect.
            transaction.categoryOverride = nil
            let key = matchKey(for: transaction, in: ledger)
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
    /// The category after applying a per-transaction override, then user rules,
    /// a confirmed transfer pair, heuristics, and finally the provider mapping.
    ///
    /// The override is first because it's the most specific statement the user
    /// can make — it's about this transaction and nothing else. A matched
    /// transfer pair then outranks the provider category and the descriptor
    /// heuristics, since seeing the money land in another of your accounts is
    /// far better evidence than any keyword, but it still yields to an explicit
    /// user rule so a wrong match can be corrected.
    func resolvedCategory(using rules: [CategoryRule]) -> SpendCategory {
        if let categoryOverride { return categoryOverride }
        if transferPairId != nil,
           CategoryResolver.userRuleCategory(name: name, merchant: merchantName, rules: rules) == nil {
            return .transfer
        }
        return CategoryResolver.resolve(
            name: name,
            merchant: merchantName,
            plaidPrimary: categoryPrimary,
            rules: rules
        )
    }
}
