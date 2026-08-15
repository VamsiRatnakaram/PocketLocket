import XCTest
@testable import PocketLocket

@MainActor
final class SavingsSuggestionsCoordinatorTests: XCTestCase {
    private let currentMonth = DateInterval(
        start: Date(timeIntervalSince1970: 1_700_000_000),
        duration: 31 * 24 * 60 * 60
    )

    private func key(
        _ dataHash: Int,
        monthlyBudget: Double = 3_000
    ) -> SavingsSuggestionsCache.InputsKey {
        SavingsSuggestionsCache.InputsKey(
            dataHash: dataHash,
            rulesHash: 1,
            excludedAccountsRaw: "",
            monthlyBudget: monthlyBudget,
            monthStart: currentMonth.start
        )
    }

    private func request(
        _ dataHash: Int,
        monthlyBudget: Double = 3_000
    ) -> SavingsSuggestionsCoordinator.Request {
        SavingsSuggestionsCoordinator.Request(
            key: key(dataHash, monthlyBudget: monthlyBudget)
        )
    }

    private var previousMonth: DateInterval {
        DateInterval(
            start: currentMonth.start.addingTimeInterval(-31 * 24 * 60 * 60),
            end: currentMonth.start
        )
    }

    private func transaction(
        name: String = "ACME",
        amount: Double = 25,
        category: String? = nil
    ) -> AnalysisTransaction {
        AnalysisTransaction(
            name: name,
            merchantName: nil,
            amount: amount,
            date: currentMonth.start.addingTimeInterval(60),
            categoryPrimary: category
        )
    }

    func testEngineResolvesRulesAndBuildsSuggestions() async throws {
        let engine = SavingsSuggestionsEngine()
        let result = await engine.suggestions(
            for: SavingsSuggestionsComputeRequest(
                key: key(1),
                transactions: [transaction()],
                rules: [CategoryRuleSpec(matchText: "acme", category: .groceries)],
                currentMonth: currentMonth,
                previousMonth: previousMonth,
                monthlyBudget: 3_000
            )
        )

        let suggestions = try XCTUnwrap(result)
        XCTAssertTrue(suggestions.contains { $0.id == "top-category-groceries" })
        XCTAssertTrue(suggestions.contains { $0.id == "budget-status" })
    }

    func testUnchangedRequestComputesOnce() async {
        let counter = Counter()
        let coordinator = SavingsSuggestionsCoordinator(
            debounce: .zero,
            cache: SavingsSuggestionsCache()
        ) { request in
            counter.increment()
            return SavingsAdvisor.suggestions([], monthlyBudget: request.monthlyBudget)
        }

        refresh(coordinator, request: request(1))
        await coordinator.activeTask?.value
        refresh(coordinator, request: request(1))
        await coordinator.activeTask?.value

        XCTAssertEqual(counter.value, 1)
    }

    func testRecomputeKeepsPreviousSuggestionsVisible() async throws {
        let coordinator = SavingsSuggestionsCoordinator(
            debounce: .zero,
            cache: SavingsSuggestionsCache()
        ) { request in
            [
                SavingsSuggestion(
                    id: "result-\(request.key.dataHash)",
                    title: "Result",
                    detail: "Detail",
                    monthlyImpact: 1,
                    symbol: "leaf",
                    tint: .green
                )
            ]
        }

        refresh(coordinator, request: request(1))
        await coordinator.activeTask?.value
        XCTAssertEqual(coordinator.suggestions?.first?.id, "result-1")

        refresh(coordinator, request: request(2))
        XCTAssertEqual(
            coordinator.suggestions?.first?.id,
            "result-1",
            "refreshing data must not replace the content with a spinner"
        )
        await coordinator.activeTask?.value
        XCTAssertEqual(coordinator.suggestions?.first?.id, "result-2")
    }

    func testBudgetOnlyChangeBypassesDebounce() async {
        let budgetRefreshStarted = expectation(description: "Budget refresh started")
        let coordinator = SavingsSuggestionsCoordinator(
            debounce: .seconds(30),
            cache: SavingsSuggestionsCache()
        ) { request in
            if request.monthlyBudget == 4_000 {
                budgetRefreshStarted.fulfill()
            }
            return [Self.suggestion(for: Int(request.monthlyBudget))]
        }

        refresh(coordinator, request: request(1))
        await coordinator.activeTask?.value

        refresh(coordinator, request: request(1, monthlyBudget: 4_000))
        await fulfillment(of: [budgetRefreshStarted], timeout: 0.25)
        await coordinator.activeTask?.value

        XCTAssertEqual(coordinator.suggestions?.first?.id, "result-4000")
    }

    func testRecreatedCoordinatorReadsSharedCacheWithoutComputing() async {
        let cache = SavingsSuggestionsCache()
        let firstCounter = Counter()
        let first = SavingsSuggestionsCoordinator(debounce: .zero, cache: cache) { request in
            firstCounter.increment()
            return [Self.suggestion(for: request.key.dataHash)]
        }

        refresh(first, request: request(1))
        await first.activeTask?.value

        let secondCounter = Counter()
        let second = SavingsSuggestionsCoordinator(debounce: .zero, cache: cache) { request in
            secondCounter.increment()
            return [Self.suggestion(for: request.key.dataHash)]
        }
        refresh(second, request: request(1))
        await second.activeTask?.value

        XCTAssertEqual(firstCounter.value, 1)
        XCTAssertEqual(secondCounter.value, 0)
        XCTAssertEqual(second.suggestions?.first?.id, "result-1")
    }

    func testSupersededNonCooperativeResultCannotOverwriteStateOrCache() async {
        let cache = SavingsSuggestionsCache()
        let gate = ComputeGate()
        let coordinator = SavingsSuggestionsCoordinator(debounce: .zero, cache: cache) { request in
            await gate.result(for: request.key.dataHash)
        }

        refresh(coordinator, request: request(1))
        let staleTask = coordinator.activeTask
        await gate.waitUntilStarted(1)

        refresh(coordinator, request: request(2))
        let currentTask = coordinator.activeTask
        await gate.waitUntilStarted(2)

        await gate.finish(2)
        await currentTask?.value
        XCTAssertEqual(coordinator.suggestions?.first?.id, "result-2")
        XCTAssertNotNil(cache.value(for: key(2)))

        // This compute ignores cancellation and finishes last. Both the
        // rendered state and cache must remain on the newer request.
        await gate.finish(1)
        await staleTask?.value
        XCTAssertEqual(coordinator.suggestions?.first?.id, "result-2")
        XCTAssertNotNil(cache.value(for: key(2)))
        XCTAssertNil(cache.value(for: key(1)))
    }

    func testSuspendCancelsPublishButKeepsDisplayedSuggestions() async {
        let cache = SavingsSuggestionsCache()
        cache.store([Self.suggestion(for: 1)], for: key(1))
        let gate = ComputeGate()
        let coordinator = SavingsSuggestionsCoordinator(debounce: .zero, cache: cache) { request in
            await gate.result(for: request.key.dataHash)
        }

        refresh(coordinator, request: request(1))
        refresh(coordinator, request: request(2))
        let task = coordinator.activeTask
        await gate.waitUntilStarted(2)

        coordinator.suspend()
        await gate.finish(2)
        await task?.value

        XCTAssertEqual(coordinator.suggestions?.first?.id, "result-1")
        XCTAssertFalse(coordinator.isRecomputing)
        XCTAssertNil(coordinator.latestRequest)
        XCTAssertNil(cache.value(for: key(2)))
    }

    nonisolated private static func suggestion(for dataHash: Int) -> SavingsSuggestion {
        SavingsSuggestion(
            id: "result-\(dataHash)",
            title: "Result",
            detail: "Detail",
            monthlyImpact: 1,
            symbol: "leaf",
            tint: .green
        )
    }

    private func refresh(
        _ coordinator: SavingsSuggestionsCoordinator,
        request: SavingsSuggestionsCoordinator.Request
    ) {
        coordinator.refresh(
            request,
            transactions: [transaction()],
            rules: [],
            currentMonth: currentMonth,
            previousMonth: previousMonth,
            monthlyBudget: request.key.monthlyBudget
        )
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }
    }

    /// Deliberately ignores task cancellation so stale-result guards are
    /// tested independently from cooperative cancellation.
    private actor ComputeGate {
        typealias Continuation = CheckedContinuation<[SavingsSuggestion]?, Never>

        private var continuations: [Int: Continuation] = [:]
        private var started: Set<Int> = []
        private var startWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

        func result(for dataHash: Int) async -> [SavingsSuggestion]? {
            started.insert(dataHash)
            startWaiters.removeValue(forKey: dataHash)?.forEach { $0.resume() }
            return await withCheckedContinuation { continuation in
                continuations[dataHash] = continuation
            }
        }

        func waitUntilStarted(_ dataHash: Int) async {
            if started.contains(dataHash) { return }
            await withCheckedContinuation { continuation in
                startWaiters[dataHash, default: []].append(continuation)
            }
        }

        func finish(_ dataHash: Int) {
            continuations.removeValue(forKey: dataHash)?
                .resume(returning: [SavingsSuggestionsCoordinatorTests.suggestion(for: dataHash)])
        }
    }
}
