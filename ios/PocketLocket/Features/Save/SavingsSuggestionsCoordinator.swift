import Foundation
import Observation

struct SavingsSuggestionsComputeRequest: Sendable {
    var key: SavingsSuggestionsCache.InputsKey
    var transactions: [AnalysisTransaction]
    var rules: [CategoryRuleSpec]
    var currentMonth: DateInterval
    var previousMonth: DateInterval
    var monthlyBudget: Double
}

/// Resolves categories and builds suggestions away from the main actor.
actor SavingsSuggestionsEngine {
    static let shared = SavingsSuggestionsEngine()

    func suggestions(for request: SavingsSuggestionsComputeRequest) -> [SavingsSuggestion]? {
        let index = CategoryRuleIndex(specs: request.rules)
        var current: [SavingsAdvisor.Input] = []
        var previous: [SavingsAdvisor.Input] = []
        current.reserveCapacity(request.transactions.count)
        previous.reserveCapacity(request.transactions.count)

        for (offset, transaction) in request.transactions.enumerated() {
            if offset % 256 == 0, Task.isCancelled { return nil }

            let input = SavingsAdvisor.Input(
                title: transaction.title,
                amount: transaction.amount,
                category: transaction.resolvedCategory(using: index),
                isSubscription: MerchantHeuristics.isLikelySubscription(
                    (transaction.merchantName ?? "") + " " + transaction.name
                )
            )
            if Self.contains(transaction.date, in: request.currentMonth) {
                current.append(input)
            } else if Self.contains(transaction.date, in: request.previousMonth) {
                previous.append(input)
            }
        }

        return SavingsAdvisor.suggestions(
            current,
            previous: previous,
            monthlyBudget: request.monthlyBudget
        )
    }

    private static func contains(_ date: Date, in interval: DateInterval) -> Bool {
        date >= interval.start && date < interval.end
    }
}

/// Owns cancellation, stale-result protection, and display state for Save.
@Observable
@MainActor
final class SavingsSuggestionsCoordinator {
    struct Request: Equatable, Sendable {
        var key: SavingsSuggestionsCache.InputsKey
    }

    typealias Compute = @Sendable (SavingsSuggestionsComputeRequest) async -> [SavingsSuggestion]?

    static let shared = SavingsSuggestionsCoordinator()

    private(set) var suggestions: [SavingsSuggestion]?
    private(set) var isRecomputing = false
    private(set) var appliedRequest: Request?
    private(set) var latestRequest: Request?
    private(set) var activeTask: Task<Void, Never>?

    private let debounce: Duration
    private let cache: SavingsSuggestionsCache
    private let compute: Compute

    init(
        debounce: Duration = .milliseconds(200),
        cache: SavingsSuggestionsCache = .shared,
        compute: @escaping Compute = { await SavingsSuggestionsEngine.shared.suggestions(for: $0) }
    ) {
        self.debounce = debounce
        self.cache = cache
        self.compute = compute
    }

    func refresh(
        _ request: Request,
        transactions: [AnalysisTransaction],
        rules: [CategoryRuleSpec],
        currentMonth: DateInterval,
        previousMonth: DateInterval,
        monthlyBudget: Double
    ) {
        latestRequest = request

        if appliedRequest == request, suggestions != nil {
            activeTask?.cancel()
            activeTask = nil
            isRecomputing = false
            return
        }

        if let cached = cache.value(for: request.key) {
            activeTask?.cancel()
            activeTask = nil
            suggestions = cached
            appliedRequest = request
            isRecomputing = false
            return
        }

        activeTask?.cancel()
        let shouldDebounce = suggestions != nil
            && !isBudgetOnlyChange(from: appliedRequest, to: request)
        let computeRequest = SavingsSuggestionsComputeRequest(
            key: request.key,
            transactions: transactions,
            rules: rules,
            currentMonth: currentMonth,
            previousMonth: previousMonth,
            monthlyBudget: monthlyBudget
        )

        activeTask = Task { [weak self] in
            guard let self else { return }
            if shouldDebounce {
                do {
                    try await Task.sleep(for: self.debounce)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            self.isRecomputing = true
            guard let result = await self.compute(computeRequest) else { return }
            guard !Task.isCancelled, self.latestRequest == request else { return }
            self.cache.store(result, for: request.key)
            self.suggestions = result
            self.appliedRequest = request
            self.isRecomputing = false
        }
    }

    private func isBudgetOnlyChange(from previous: Request?, to current: Request) -> Bool {
        guard let previous else { return false }
        let oldKey = previous.key
        let newKey = current.key
        return oldKey.monthlyBudget != newKey.monthlyBudget
            && oldKey.dataHash == newKey.dataHash
            && oldKey.rulesHash == newKey.rulesHash
            && oldKey.excludedAccountsRaw == newKey.excludedAccountsRaw
            && oldKey.monthStart == newKey.monthStart
    }

    /// Cancels hidden-tab work and invalidates its publish token. The previous
    /// suggestions remain available for an instant return to Save.
    func suspend() {
        activeTask?.cancel()
        activeTask = nil
        latestRequest = nil
        isRecomputing = false
    }
}
