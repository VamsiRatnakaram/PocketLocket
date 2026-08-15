import Foundation

/// Cheap content signatures for SwiftData-backed lists, used as `DerivedCache`
/// keys.
///
/// Hashing a handful of scalar fields per record costs orders of magnitude less
/// than the filtering, categorization and sorting it guards, so it is worth
/// paying on every render to avoid paying the real cost.
///
/// Counting records is *not* enough. Editing a transaction's category or
/// renaming a merchant leaves the count identical, and a key that missed those
/// changes would pin a stale list on screen until something unrelated
/// invalidated it.
enum RecordHash {
    static func transactions(_ transactions: [TransactionRecord]) -> Int {
        var hasher = Hasher()
        hasher.combine(transactions.count)
        for txn in transactions {
            hasher.combine(txn.id)
            hasher.combine(txn.amount)
            hasher.combine(txn.date)
            // Both, not `title`. `title` collapses to `merchantName` whenever
            // one is set, which would hide an edit to `name` — and `name`
            // feeds both category resolution and search, so the cache would
            // keep serving rows filtered and categorized off the old value.
            hasher.combine(txn.name)
            hasher.combine(txn.merchantName)
            hasher.combine(txn.categoryPrimary)
            hasher.combine(txn.accountId)
            // Both change a transaction's resolved category without touching
            // any other hashed field, so omitting them would pin a stale list
            // after a recategorization or a newly matched transfer pair.
            hasher.combine(txn.categoryOverrideRaw)
            hasher.combine(txn.transferPairId)
        }
        return hasher.finalize()
    }

    static func rules(_ rules: [CategoryRule]) -> Int {
        var hasher = Hasher()
        hasher.combine(rules.count)
        for rule in rules {
            hasher.combine(rule.matchText)
            hasher.combine(rule.categoryRaw)
        }
        return hasher.finalize()
    }
}
