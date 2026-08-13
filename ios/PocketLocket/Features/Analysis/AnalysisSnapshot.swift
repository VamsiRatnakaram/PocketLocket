import Foundation

/// Everything the Analysis tab renders, computed in a single pass.
///
/// Previously each section was a separate computed property on the view, so a
/// single `body` evaluation ran `merchantStats` three times (unfiltered,
/// filtered, and again inside `recurringMerchants`) and re-resolved every
/// transaction's category several times over — and SwiftUI re-evaluates `body`
/// many times per tab load. Bundling the results into one value lets the view
/// compute once per *data* change instead of once per render pass.
struct AnalysisSnapshot: Sendable {
    var isEmpty: Bool = true
    var availableCategories: [SpendCategory] = []
    var topByFrequency: [MerchantAnalytics.MerchantStats] = []
    var topBySpend: [MerchantAnalytics.MerchantStats] = []
    var recurring: [MerchantAnalytics.MerchantStats] = []
    var categoryAverages: [MerchantAnalytics.CategoryAverage] = []
    var categoryMonthly: [MerchantAnalytics.CategoryMonth] = []

    static func make(
        inputs: [MerchantAnalytics.Input],
        categoryFilter: SpendCategory?,
        merchantLimit: Int = 8,
        minRecurringMonths: Int = 3
    ) -> AnalysisSnapshot {
        let allStats = MerchantAnalytics.merchantStats(inputs)
        guard !allStats.isEmpty else { return AnalysisSnapshot() }

        let present = Set(inputs.filter { $0.category.isSpending }.map(\.category))
        let available = SpendCategory.allCases.filter { present.contains($0) }

        let filteredInputs: [MerchantAnalytics.Input]
        let filteredStats: [MerchantAnalytics.MerchantStats]
        if let categoryFilter {
            filteredInputs = inputs.filter { $0.category == categoryFilter }
            filteredStats = MerchantAnalytics.merchantStats(filteredInputs)
        } else {
            filteredInputs = inputs
            filteredStats = allStats
        }

        return AnalysisSnapshot(
            isEmpty: false,
            availableCategories: available,
            topByFrequency: MerchantAnalytics.topByFrequency(filteredStats, limit: merchantLimit),
            topBySpend: MerchantAnalytics.topBySpend(filteredStats, limit: merchantLimit),
            recurring: MerchantAnalytics.recurringMerchants(
                filteredInputs, minMonths: minRecurringMonths, stats: filteredStats
            ),
            categoryAverages: MerchantAnalytics.categoryAverages(filteredInputs),
            categoryMonthly: MerchantAnalytics.categoryMonthlyTotals(filteredInputs)
        )
    }
}

/// Memoizes the two expensive stages of the Analysis pipeline so SwiftUI's
/// repeated `body` evaluations reuse work instead of redoing it.
///
/// Correctness comes from content-addressed keys: the keys hash the actual
/// transaction fields and rule set that feed the computation, so any edit,
/// sync, or recategorization produces a different key and forces a recompute.
/// Nothing is memoized permanently — only the most recent key is retained.
final class AnalysisSnapshotCache {
    struct InputsKey: Equatable, Sendable {
        var dataHash: Int
        var rulesHash: Int
        var excludedAccountsRaw: String
        var range: AnalysisTimeRange
    }

    private var inputsKey: InputsKey?
    private var inputs: [MerchantAnalytics.Input] = []

    private var snapshotKey: InputsKey?
    private var snapshotFilter: SpendCategory?
    private var hasSnapshot = false
    private var snapshot = AnalysisSnapshot()

    /// Content hash of the transactions that feed analysis. Hashing a few
    /// scalar fields per record is orders of magnitude cheaper than the
    /// regex-based normalization/categorization it guards.
    static func dataHash(_ transactions: [TransactionRecord]) -> Int {
        var hasher = Hasher()
        hasher.combine(transactions.count)
        for txn in transactions {
            hasher.combine(txn.id)
            hasher.combine(txn.amount)
            hasher.combine(txn.date)
            hasher.combine(txn.title)
            hasher.combine(txn.categoryPrimary)
            hasher.combine(txn.accountId)
        }
        return hasher.finalize()
    }

    static func rulesHash(_ rules: [CategoryRule]) -> Int {
        var hasher = Hasher()
        hasher.combine(rules.count)
        for rule in rules {
            hasher.combine(rule.matchText)
            hasher.combine(rule.categoryRaw)
        }
        return hasher.finalize()
    }

    /// Returns the analysis snapshot for this data/filter combination,
    /// recomputing only the stages whose inputs actually changed.
    func snapshot(
        key: InputsKey,
        categoryFilter: SpendCategory?,
        buildInputs: () -> [MerchantAnalytics.Input]
    ) -> AnalysisSnapshot {
        if inputsKey != key {
            inputs = buildInputs()
            inputsKey = key
            hasSnapshot = false
        }
        if !hasSnapshot || snapshotKey != key || snapshotFilter != categoryFilter {
            snapshot = AnalysisSnapshot.make(inputs: inputs, categoryFilter: categoryFilter)
            snapshotKey = key
            snapshotFilter = categoryFilter
            hasSnapshot = true
        }
        return snapshot
    }
}
