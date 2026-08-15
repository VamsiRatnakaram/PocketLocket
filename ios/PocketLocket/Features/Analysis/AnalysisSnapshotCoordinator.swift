import Foundation
import Observation

/// A transaction reduced to the plain values analysis needs.
///
/// `TransactionRecord` is a SwiftData `@Model` bound to its `ModelContext`, so
/// it can never leave the main thread. The view extracts these value copies on
/// the main thread (cheap: five scalar/string fields per row) and only they are
/// handed to the background analysis. Copying also makes the background work
/// immune to rows being deleted or edited while it runs.
struct AnalysisTransaction: Sendable, Hashable {
    let name: String
    let merchantName: String?
    let amount: Double
    let date: Date
    let categoryPrimary: String?
    /// Carried so background resolution matches `TransactionRecord.resolvedCategory`
    /// exactly. Without these the Analysis tab would categorize differently
    /// from Home and Transactions for the same transaction.
    let categoryOverride: SpendCategory?
    let isMatchedTransfer: Bool

    init(
        name: String,
        merchantName: String?,
        amount: Double,
        date: Date,
        categoryPrimary: String?,
        categoryOverride: SpendCategory? = nil,
        isMatchedTransfer: Bool = false
    ) {
        self.name = name
        self.merchantName = merchantName
        self.amount = amount
        self.date = date
        self.categoryPrimary = categoryPrimary
        self.categoryOverride = categoryOverride
        self.isMatchedTransfer = isMatchedTransfer
    }

    init(record: TransactionRecord) {
        self.init(
            name: record.name,
            merchantName: record.merchantName,
            amount: record.amount,
            date: record.date,
            categoryPrimary: record.categoryPrimary,
            categoryOverride: record.categoryOverride,
            isMatchedTransfer: record.transferPairId != nil
        )
    }

    /// Mirrors `TransactionRecord.title`.
    var title: String {
        if let merchantName, !merchantName.isEmpty { return merchantName }
        return name
    }

    /// Mirrors `TransactionRecord.resolvedCategory(using:)` without carrying a
    /// SwiftData model across an actor boundary.
    func resolvedCategory(using index: CategoryRuleIndex) -> SpendCategory {
        if let categoryOverride { return categoryOverride }
        let haystack = ((merchantName ?? "") + " " + name).lowercased()
        if let ruleCategory = index.category(for: haystack) { return ruleCategory }
        if isMatchedTransfer { return .transfer }
        return CategoryResolver.resolve(
            name: name,
            merchant: merchantName,
            plaidPrimary: categoryPrimary,
            index: index
        )
    }
}

/// A self-contained, `Sendable` description of one analysis computation.
struct AnalysisComputeRequest: Sendable {
    var key: AnalysisSnapshotCache.InputsKey
    var window: DateInterval?
    var chartEnd: Date? = nil
    var categoryFilter: SpendCategory?
    var transactions: [AnalysisTransaction]
    var rules: [CategoryRuleSpec]
    var groupingRules: [MerchantGroupingRuleSpec] = []
}

/// Runs the analysis pipeline off the main thread.
///
/// An `actor` gives three things at once: the work executes on the cooperative
/// thread pool (never blocking the UI), concurrent requests are serialized (so
/// a burst of syncs can't spin up N parallel full analyses), and the two-stage
/// memo below is mutated under the actor's isolation.
///
/// The memo lives here rather than in the view so completed work remains
/// available when Analysis temporarily detaches its query-owning data driver.
actor AnalysisComputeEngine {
    static let shared = AnalysisComputeEngine()

    private let cache = AnalysisSnapshotCache()

    /// Number of computations that were *not* served from the memo. Exposed
    /// for tests.
    private(set) var missCount = 0

    /// Returns nil if the calling task was cancelled partway through.
    ///
    /// The actor runs one request at a time, so work nobody will ever look at
    /// still made the newest request wait for it. Checking cancellation inside
    /// the loop lets a superseded pass release the actor early.
    func snapshot(for request: AnalysisComputeRequest) -> AnalysisSnapshot? {
        cache.snapshot(
            key: request.key,
            window: request.window,
            chartEnd: request.chartEnd,
            categoryFilter: request.categoryFilter,
            groupingRules: request.groupingRules
        ) {
            self.missCount += 1
            // Category resolution is the expensive half (token matching against
            // the rule index plus the heuristics table), so it happens here,
            // off the main thread, rather than during extraction.
            let index = CategoryRuleIndex(specs: request.rules)
            var inputs: [MerchantAnalytics.Input] = []
            inputs.reserveCapacity(request.transactions.count)
            for (offset, txn) in request.transactions.enumerated() {
                // Batched so the check itself doesn't show up in the profile.
                if offset % 256 == 0, Task.isCancelled { return nil }
                inputs.append(
                    MerchantAnalytics.Input(
                        title: txn.title,
                        amount: txn.amount,
                        category: txn.resolvedCategory(using: index),
                        date: txn.date
                    )
                )
            }
            return inputs
        }
    }
}

/// Owns the async lifecycle of the Analysis tab's snapshot: debouncing,
/// cancellation, supersede protection, and the tri-state the UI renders.
///
/// Deliberately a plain class rather than logic buried in the `View` so the
/// ordering rules (a stale result must never overwrite a newer one; an
/// unchanged request must not recompute) are directly unit-testable.
@Observable
@MainActor
final class AnalysisSnapshotCoordinator {
    /// Tri-state. `idle`/`loading` are distinct from `loaded` with an empty
    /// snapshot: the "No trends yet" empty state may only be shown for the
    /// latter, otherwise it flashes while the first computation is in flight.
    enum Phase {
        case idle
        case loading
        case loaded(AnalysisSnapshot)

        var snapshot: AnalysisSnapshot? {
            if case let .loaded(snapshot) = self { return snapshot }
            return nil
        }

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    /// Everything that determines the rendered result.
    struct Request: Equatable, Sendable {
        var key: AnalysisSnapshotCache.InputsKey
        var window: DateInterval? = nil
        var chartEnd: Date? = nil
        var categoryFilter: SpendCategory?
    }

    /// Returns nil when the pass was superseded partway through.
    typealias Compute = @Sendable (AnalysisComputeRequest) async -> AnalysisSnapshot?

    /// Shared so re-entering this tab later can render the last result
    /// immediately instead of flashing a spinner.
    static let shared = AnalysisSnapshotCoordinator()

    private(set) var phase: Phase = .idle
    /// True while a recompute runs *behind* an already-displayed snapshot.
    private(set) var isRecomputing = false

    /// The request whose result is on screen.
    private(set) var appliedRequest: Request?
    /// The newest request asked for; results for anything else are stale.
    private(set) var latestRequest: Request?
    /// Exposed so callers/tests can await the in-flight computation.
    private(set) var activeTask: Task<Void, Never>?

    private let debounce: Duration
    private let compute: Compute

    /// - Parameter debounce: Delay before starting heavy work when a snapshot
    ///   is already displayed. 200ms comfortably swallows the burst of `@Query`
    ///   republishes a batched SimpleFIN sync produces, while staying under the
    ///   ~250ms threshold where an update stops feeling immediate. The first
    ///   load is never debounced.
    init(
        debounce: Duration = .milliseconds(200),
        compute: @escaping Compute = { await AnalysisComputeEngine.shared.snapshot(for: $0) }
    ) {
        self.debounce = debounce
        self.compute = compute
    }

    var snapshot: AnalysisSnapshot? { phase.snapshot }

    /// True only for a genuine first load — no previous snapshot to show.
    var isInitialLoading: Bool { phase.snapshot == nil }

    /// Requests a snapshot for `request`, computing it off the main thread.
    ///
    /// `transactions`/`rules` must already be extracted from SwiftData by the
    /// caller on the main thread.
    func refresh(
        _ request: Request,
        transactions: [AnalysisTransaction],
        rules: [CategoryRuleSpec],
        groupingRules: [MerchantGroupingRuleSpec] = []
    ) {
        markRequested(request)

        // Already showing exactly this result — repeated renders are free.
        if appliedRequest == request, phase.snapshot != nil {
            activeTask?.cancel()
            activeTask = nil
            isRecomputing = false
            return
        }

        // Supersede any in-flight work; its result can no longer be applied.
        activeTask?.cancel()

        let shouldDebounce = phase.snapshot != nil
        let computeRequest = AnalysisComputeRequest(
            key: request.key,
            window: request.window,
            chartEnd: request.chartEnd,
            categoryFilter: request.categoryFilter,
            transactions: transactions,
            rules: rules,
            groupingRules: groupingRules
        )

        activeTask = Task { [weak self] in
            guard let self else { return }
            if shouldDebounce {
                do {
                    try await Task.sleep(for: self.debounce)
                } catch {
                    return // Superseded during the debounce window.
                }
            }
            guard !Task.isCancelled else { return }
            self.beginComputing()
            guard let result = await self.compute(computeRequest) else { return }
            guard !Task.isCancelled else { return }
            self.apply(result, for: request)
        }
    }

    /// Stops work and detaches the current request when Analysis becomes
    /// hidden. A non-cooperative compute closure still cannot publish because
    /// both its task cancellation and latest-request guards will fail.
    func suspend() {
        activeTask?.cancel()
        activeTask = nil
        latestRequest = nil
        isRecomputing = false
    }

    /// Records the newest request. Split out so the supersede guard can be
    /// tested without running the async machinery.
    func markRequested(_ request: Request) {
        latestRequest = request
    }

    /// Enters the loading state. Keeps any previously loaded snapshot on
    /// screen — during a sync the content must not flash away.
    func beginComputing() {
        if phase.snapshot == nil { phase = .loading }
        isRecomputing = true
    }

    /// Publishes `snapshot` unless a newer request has superseded this one.
    /// - Returns: whether the result was applied.
    @discardableResult
    func apply(_ snapshot: AnalysisSnapshot, for request: Request) -> Bool {
        guard latestRequest == request else { return false }
        phase = .loaded(snapshot)
        appliedRequest = request
        isRecomputing = false
        return true
    }
}
