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
    var categoryCumulative: [MerchantAnalytics.CategoryMonth] = []

    static func make(
        inputs: [MerchantAnalytics.Input],
        window: DateInterval? = nil,
        categoryFilter: SpendCategory?,
        chartEnd: Date? = nil,
        groupingRules: [MerchantGroupingRuleSpec] = [],
        merchantLimit: Int = 8,
        minRecurringMonths: Int = 3
    ) -> AnalysisSnapshot {
        let dataCoverageStart = inputs.map(\.date).min()
        let selectedEnd = window?.end.addingTimeInterval(-1)
        let cumulativeEnd = [chartEnd, selectedEnd].compactMap { $0 }.min()
        let selectedInputs = window.map { interval in
            inputs.filter { $0.date >= interval.start && $0.date < interval.end }
        } ?? inputs
        let domainStats = MerchantAnalytics.merchantStats(inputs, groupingRules: groupingRules)
        guard !domainStats.isEmpty else { return AnalysisSnapshot() }
        let allStats = window == nil
            ? domainStats
            : MerchantAnalytics.merchantStats(selectedInputs, groupingRules: groupingRules)

        // Positive amounts only, matching what every section below counts —
        // otherwise a category with nothing but refunds offers a chip that
        // filters to an empty screen.
        let present = Set(selectedInputs.filter { $0.category.isSpending && $0.amount > 0 }.map(\.category))
        let available = SpendCategory.allCases.filter { present.contains($0) }

        let filteredInputs: [MerchantAnalytics.Input]
        let filteredStats: [MerchantAnalytics.MerchantStats]
        if let categoryFilter {
            filteredInputs = selectedInputs.filter { $0.category == categoryFilter }
            filteredStats = MerchantAnalytics.merchantStats(
                filteredInputs,
                groupingRules: groupingRules
            )
        } else {
            filteredInputs = selectedInputs
            filteredStats = allStats
        }

        return AnalysisSnapshot(
            isEmpty: false,
            availableCategories: available,
            topByFrequency: MerchantAnalytics.topByFrequency(filteredStats, limit: merchantLimit),
            topBySpend: MerchantAnalytics.topBySpend(filteredStats, limit: merchantLimit),
            recurring: MerchantAnalytics.recurringMerchants(
                filteredInputs,
                minMonths: minRecurringMonths,
                stats: filteredStats,
                groupingRules: groupingRules
            ),
            // Deliberately unfiltered. These two drive the chart and the
            // averages list, which render *above* the category chips — letting
            // the filter resize them meant tapping a chip collapsed the chart
            // to a single line, shrank the list, and yanked the chip row out
            // from under your finger. The filter scopes the merchant sections
            // below it; the chart has its own tap-to-hide legend for focus.
            categoryAverages: MerchantAnalytics.categoryAverages(
                selectedInputs,
                window: window,
                dataCoverageStart: dataCoverageStart
            ),
            categoryMonthly: MerchantAnalytics.categoryTrendTotals(inputs, through: chartEnd),
            categoryCumulative: MerchantAnalytics.categoryCumulativeTotals(
                selectedInputs,
                from: window?.start,
                through: cumulativeEnd
            )
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
        var groupingRulesHash: Int = 0
        var excludedAccountsRaw: String
    }

    private var inputsKey: InputsKey?
    private var inputs: [MerchantAnalytics.Input] = []

    private var snapshotKey: InputsKey?
    private var snapshotFilter: SpendCategory?
    private var snapshotWindow: DateInterval?
    private var snapshotChartEnd: Date?
    private var hasSnapshot = false
    private var snapshot = AnalysisSnapshot()

    /// Delegated to `RecordHash` so the analysis cache and the list caches can
    /// never disagree about what counts as a change.
    static func dataHash(_ transactions: [TransactionRecord]) -> Int {
        RecordHash.transactions(transactions)
    }

    static func rulesHash(_ rules: [CategoryRule]) -> Int {
        RecordHash.rules(rules)
    }

    static func groupingRulesHash(_ rules: [MerchantGroupingRule]) -> Int {
        RecordHash.groupingRules(rules)
    }

    /// Returns the analysis snapshot for this data/filter combination,
    /// recomputing only the stages whose inputs actually changed.
    func snapshot(
        key: InputsKey,
        window: DateInterval? = nil,
        chartEnd: Date? = nil,
        categoryFilter: SpendCategory?,
        groupingRules: [MerchantGroupingRuleSpec] = [],
        buildInputs: () -> [MerchantAnalytics.Input]?
    ) -> AnalysisSnapshot? {
        if inputsKey != key {
            // `buildInputs` returns nil when it bailed out early because the
            // request was superseded. Memoizing a half-built pass would pin a
            // wrong snapshot under a key that claims to be complete.
            guard let built = buildInputs() else { return nil }
            inputs = built
            inputsKey = key
            hasSnapshot = false
        }
        if !hasSnapshot
            || snapshotKey != key
            || snapshotFilter != categoryFilter
            || snapshotWindow != window
            || snapshotChartEnd != chartEnd
        {
            snapshot = AnalysisSnapshot.make(
                inputs: inputs,
                window: window,
                categoryFilter: categoryFilter,
                chartEnd: chartEnd,
                groupingRules: groupingRules
            )
            snapshotKey = key
            snapshotFilter = categoryFilter
            snapshotWindow = window
            snapshotChartEnd = chartEnd
            hasSnapshot = true
        }
        return snapshot
    }
}
