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

    init(name: String, merchantName: String?, amount: Double, date: Date, categoryPrimary: String?) {
        self.name = name
        self.merchantName = merchantName
        self.amount = amount
        self.date = date
        self.categoryPrimary = categoryPrimary
    }

    init(record: TransactionRecord) {
        self.init(
            name: record.name,
            merchantName: record.merchantName,
            amount: record.amount,
            date: record.date,
            categoryPrimary: record.categoryPrimary
        )
    }

    /// Mirrors `TransactionRecord.title`.
    var title: String {
        if let merchantName, !merchantName.isEmpty { return merchantName }
        return name
    }
}

/// A self-contained, `Sendable` description of one analysis computation.
struct AnalysisComputeRequest: Sendable {
    var key: AnalysisSnapshotCache.InputsKey
    var categoryFilter: SpendCategory?
    var transactions: [AnalysisTransaction]
    var rules: [CategoryRuleSpec]
}

/// Runs the analysis pipeline off the main thread.
///
/// An `actor` gives three things at once: the work executes on the cooperative
/// thread pool (never blocking the UI), concurrent requests are serialized (so
/// a burst of syncs can't spin up N parallel full analyses), and the two-stage
/// memo below is mutated under the actor's isolation.
///
/// The memo lives here rather than in the view so it survives view teardown —
/// `AnalysisRootView` destroys `AnalysisView` whenever you switch to the Save
/// segment, and re-entering the tab should not repay the full cost.
actor AnalysisComputeEngine {
    static let shared = AnalysisComputeEngine()

    private let cache = AnalysisSnapshotCache()

    /// Number of computations that were *not* served from the memo. Exposed
    /// for tests.
    private(set) var missCount = 0

    func snapshot(for request: AnalysisComputeRequest) -> AnalysisSnapshot {
        cache.snapshot(key: request.key, categoryFilter: request.categoryFilter) {
            self.missCount += 1
            // Category resolution is the expensive half (token matching against
            // the rule index plus the heuristics table), so it happens here,
            // off the main thread, rather than during extraction.
            let index = CategoryRuleIndex(specs: request.rules)
            return request.transactions.map { txn in
                MerchantAnalytics.Input(
                    title: txn.title,
                    amount: txn.amount,
                    category: CategoryResolver.resolve(
                        name: txn.name,
                        merchant: txn.merchantName,
                        plaidPrimary: txn.categoryPrimary,
                        index: index
                    ),
                    date: txn.date
                )
            }
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
        var categoryFilter: SpendCategory?
    }

    typealias Compute = @Sendable (AnalysisComputeRequest) async -> AnalysisSnapshot

    /// Shared because `AnalysisView` is destroyed and recreated by the
    /// Analysis/Save segmented picker; keeping the last result here means
    /// re-entering the tab renders immediately instead of flashing a spinner.
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
    func refresh(_ request: Request, transactions: [AnalysisTransaction], rules: [CategoryRuleSpec]) {
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
            categoryFilter: request.categoryFilter,
            transactions: transactions,
            rules: rules
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
            let result = await self.compute(computeRequest)
            guard !Task.isCancelled else { return }
            self.apply(result, for: request)
        }
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
