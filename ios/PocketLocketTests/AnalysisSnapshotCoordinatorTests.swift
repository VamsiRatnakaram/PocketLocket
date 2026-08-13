import XCTest
@testable import PocketLocket

@MainActor
final class AnalysisSnapshotCoordinatorTests: XCTestCase {
    private func date(_ month: Int, _ day: Int = 1) -> Date {
        DateComponents(calendar: .current, year: 2024, month: month, day: day).date!
    }

    private func key(_ dataHash: Int, rules: Int = 1) -> AnalysisSnapshotCache.InputsKey {
        AnalysisSnapshotCache.InputsKey(
            dataHash: dataHash, rulesHash: rules, excludedAccountsRaw: "", range: .all
        )
    }

    private func request(_ dataHash: Int, filter: SpendCategory? = nil) -> AnalysisSnapshotCoordinator.Request {
        AnalysisSnapshotCoordinator.Request(key: key(dataHash), categoryFilter: filter)
    }

    private var sampleTransactions: [AnalysisTransaction] {
        [
            AnalysisTransaction(name: "STARBUCKS #101", merchantName: nil, amount: 5, date: date(1), categoryPrimary: nil),
            AnalysisTransaction(name: "STARBUCKS #101", merchantName: nil, amount: 6, date: date(2), categoryPrimary: nil),
            AnalysisTransaction(name: "STARBUCKS #101", merchantName: nil, amount: 7, date: date(3), categoryPrimary: nil),
            AnalysisTransaction(name: "TRADER JOES 455", merchantName: "Trader Joes", amount: 80, date: date(1), categoryPrimary: nil),
            AnalysisTransaction(name: "TRADER JOES 455", merchantName: "Trader Joes", amount: 90, date: date(2), categoryPrimary: nil),
        ]
    }

    private func nonEmptySnapshot(_ name: String = "Starbucks") -> AnalysisSnapshot {
        AnalysisSnapshot.make(
            inputs: [MerchantAnalytics.Input(title: name, amount: 5, category: .food, date: date(1))],
            categoryFilter: nil
        )
    }

    /// Counts computations and lets the test record which requests ran.
    private final class ComputeRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var keys: [Int] = []

        var callCount: Int { lock.lock(); defer { lock.unlock() }; return keys.count }
        var recordedKeys: [Int] { lock.lock(); defer { lock.unlock() }; return keys }

        func record(_ request: AnalysisComputeRequest) {
            lock.lock(); keys.append(request.key.dataHash); lock.unlock()
        }
    }

    // MARK: - Phase / empty-state correctness

    func testFirstLoadIsLoadingNotEmpty() {
        let coordinator = AnalysisSnapshotCoordinator(compute: { _ in AnalysisSnapshot() })
        coordinator.markRequested(request(1))
        coordinator.beginComputing()

        XCTAssertTrue(coordinator.phase.isLoading)
        XCTAssertNil(coordinator.snapshot, "the empty state must not show while the first pass is in flight")
        XCTAssertTrue(coordinator.isInitialLoading)

        coordinator.apply(AnalysisSnapshot(), for: request(1))
        XCTAssertEqual(coordinator.snapshot?.isEmpty, true, "a finished, genuinely empty result may show the empty state")
        XCTAssertFalse(coordinator.isRecomputing)
    }

    func testRecomputeKeepsPreviousSnapshotVisible() {
        let coordinator = AnalysisSnapshotCoordinator(compute: { _ in AnalysisSnapshot() })
        coordinator.markRequested(request(1))
        coordinator.apply(nonEmptySnapshot(), for: request(1))

        coordinator.markRequested(request(2))
        coordinator.beginComputing()

        XCTAssertFalse(coordinator.phase.isLoading, "must not drop to a spinner mid-sync")
        XCTAssertEqual(coordinator.snapshot?.topBySpend.first?.name, "Starbucks")
        XCTAssertTrue(coordinator.isRecomputing)
        XCTAssertFalse(coordinator.isInitialLoading)
    }

    // MARK: - Supersede protection

    func testStaleResultIsNotApplied() {
        let coordinator = AnalysisSnapshotCoordinator(compute: { _ in AnalysisSnapshot() })
        let stale = request(1)
        let current = request(2)

        coordinator.markRequested(stale)
        coordinator.markRequested(current)

        XCTAssertFalse(
            coordinator.apply(nonEmptySnapshot("Stale Cafe"), for: stale),
            "a superseded computation must never overwrite newer state"
        )
        XCTAssertNil(coordinator.snapshot)

        XCTAssertTrue(coordinator.apply(nonEmptySnapshot("Fresh Cafe"), for: current))
        XCTAssertEqual(coordinator.snapshot?.topBySpend.first?.name, "Fresh Cafe")
    }

    func testFilterChangeAloneSupersedesEarlierResult() {
        let coordinator = AnalysisSnapshotCoordinator(compute: { _ in AnalysisSnapshot() })
        coordinator.markRequested(request(1, filter: .food))
        XCTAssertFalse(coordinator.apply(nonEmptySnapshot(), for: request(1, filter: nil)))
    }

    // MARK: - Async orchestration

    func testUnchangedRequestDoesNotRecompute() async {
        let recorder = ComputeRecorder()
        let coordinator = AnalysisSnapshotCoordinator(debounce: .milliseconds(10)) { req in
            recorder.record(req)
            return AnalysisSnapshot.make(inputs: [], categoryFilter: nil)
        }

        coordinator.refresh(request(1), transactions: sampleTransactions, rules: [])
        await coordinator.activeTask?.value
        coordinator.refresh(request(1), transactions: sampleTransactions, rules: [])
        await coordinator.activeTask?.value

        XCTAssertEqual(recorder.callCount, 1, "an unchanged request must not recompute")
    }

    func testFirstLoadIsNotDebouncedAndProducesSnapshot() async {
        let coordinator = AnalysisSnapshotCoordinator(debounce: .seconds(30)) { req in
            await AnalysisComputeEngine().snapshot(for: req)
        }

        coordinator.refresh(request(1), transactions: sampleTransactions, rules: [])
        await coordinator.activeTask?.value

        XCTAssertEqual(coordinator.snapshot?.isEmpty, false)
        XCTAssertEqual(
            Set(coordinator.snapshot?.topBySpend.map(\.name) ?? []),
            ["Starbucks", "Trader Joes"]
        )
    }

    func testRapidChangesCoalesceToTheLatestRequest() async {
        let recorder = ComputeRecorder()
        let coordinator = AnalysisSnapshotCoordinator(debounce: .milliseconds(50)) { req in
            recorder.record(req)
            return AnalysisSnapshot.make(inputs: [], categoryFilter: nil)
        }

        // Seed a first result so subsequent refreshes take the debounced path.
        coordinator.refresh(request(1), transactions: sampleTransactions, rules: [])
        await coordinator.activeTask?.value
        XCTAssertEqual(recorder.callCount, 1)

        // Simulates a batched sync republishing @Query several times.
        for hash in 2...5 {
            coordinator.refresh(request(hash), transactions: sampleTransactions, rules: [])
        }
        await coordinator.activeTask?.value

        XCTAssertEqual(recorder.recordedKeys, [1, 5], "only the newest key in a burst should run")
        XCTAssertEqual(coordinator.appliedRequest, request(5))
    }

    // MARK: - Background engine

    func testEngineResolvesCategoriesFromPlainRuleSpecs() async {
        let engine = AnalysisComputeEngine()
        let request = AnalysisComputeRequest(
            key: key(7),
            categoryFilter: nil,
            transactions: [
                AnalysisTransaction(name: "ACME WIDGETS", merchantName: nil, amount: 25, date: date(1), categoryPrimary: nil),
                AnalysisTransaction(name: "ACME WIDGETS", merchantName: nil, amount: 35, date: date(2), categoryPrimary: nil),
            ],
            rules: [CategoryRuleSpec(matchText: "acme widgets", category: .groceries)]
        )

        let snapshot = await engine.snapshot(for: request)
        XCTAssertEqual(snapshot.topBySpend.first?.category, .groceries)
        XCTAssertEqual(snapshot.availableCategories, [.groceries])
    }

    /// The engine memoizes resolved inputs separately from the snapshot, so
    /// changing only the category filter must not re-resolve categories.
    func testEngineReusesResolvedInputsAcrossFilterChanges() async {
        let engine = AnalysisComputeEngine()
        let base = AnalysisComputeRequest(
            key: key(11),
            categoryFilter: nil,
            transactions: sampleTransactions,
            rules: [CategoryRuleSpec(matchText: "trader joes", category: .groceries)]
        )

        _ = await engine.snapshot(for: base)
        var filtered = base
        filtered.categoryFilter = .groceries
        let result = await engine.snapshot(for: filtered)
        let misses = await engine.missCount

        XCTAssertEqual(misses, 1, "a filter change must reuse resolved inputs")
        XCTAssertEqual(result.topBySpend.map(\.name), ["Trader Joes"])
    }
}
