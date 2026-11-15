import Foundation
import SwiftUI

/// Builds and publishes the widget's snapshot from the app's own data.
///
/// Lives in the app target because only the app can see the ledger. Everything
/// it hands over is already-derived: it filters the same month Home filters and
/// reuses `SpendAggregator` and `SafeToSpendBasis`, so the widget's numbers come
/// from the same code that produced the app's.
///
/// Why this recomputes instead of reusing Home's cached `MonthSummary`: Home
/// caches the month *you're looking at*, which can be last month, while a widget
/// always shows the current one. Reusing the cache would leave the widget frozen
/// at whatever month happened to be on screen. The extra pass is a single O(month)
/// filter triggered by a real data change — not per render — which is a cost the
/// `Key` check below keeps off the hot path.
/// Main-actor because it reads SwiftData records, which are main-actor types.
/// It is only ever built and used from views.
@MainActor
struct WidgetSnapshotPublisher {
    let transactions: [TransactionRecord]
    let rules: [CategoryRule]
    let reimbursements: [ReimbursementAllocation]
    let monthlyBudget: Double
    let excludedAccountsRaw: String
    let categoryBudgetsRaw: String
    let safeToSpendFocusRaw: String
    let showsAmounts: Bool
    let calendar: Calendar

    init(
        transactions: [TransactionRecord],
        rules: [CategoryRule],
        reimbursements: [ReimbursementAllocation],
        monthlyBudget: Double,
        excludedAccountsRaw: String,
        categoryBudgetsRaw: String,
        safeToSpendFocusRaw: String,
        showsAmounts: Bool,
        calendar: Calendar = .current
    ) {
        self.transactions = transactions
        self.rules = rules
        self.reimbursements = reimbursements
        self.monthlyBudget = monthlyBudget
        self.excludedAccountsRaw = excludedAccountsRaw
        self.categoryBudgetsRaw = categoryBudgetsRaw
        self.safeToSpendFocusRaw = safeToSpendFocusRaw
        self.showsAmounts = showsAmounts
        self.calendar = calendar
    }

    /// Identity of "everything that could change what the widget shows".
    ///
    /// Deliberately excludes the browsed month: swiping Home back to March must
    /// not rewrite a widget that shows October.
    struct Key: Equatable {
        var dataHash: Int
        var rulesHash: Int
        var reimbursementsHash: Int
        var monthStart: Date
        var monthlyBudget: Double
        var excludedAccountsRaw: String
        var categoryBudgetsRaw: String
        var safeToSpendFocusRaw: String
        var showsAmounts: Bool
    }

    /// Cheap enough to evaluate on every render: it narrows to the current month
    /// with scalar comparisons before hashing, exactly like Home's cache key.
    func key(now: Date = Date()) -> Key {
        let monthTransactions = currentMonthTransactions(now: now)
        return Key(
            dataHash: RecordHash.transactions(monthTransactions),
            rulesHash: RecordHash.rules(rules),
            reimbursementsHash: RecordHash.reimbursements(reimbursements),
            monthStart: calendar.dateInterval(of: .month, for: now)?.start ?? now,
            monthlyBudget: monthlyBudget,
            excludedAccountsRaw: excludedAccountsRaw,
            categoryBudgetsRaw: categoryBudgetsRaw,
            safeToSpendFocusRaw: safeToSpendFocusRaw,
            showsAmounts: showsAmounts
        )
    }

    /// Publishes unless nothing the widget can show has changed, in which case
    /// `WidgetSnapshotStore` skips the write and the reload.
    ///
    /// - Returns: whether a widget reload was requested.
    @discardableResult
    func publish(now: Date = Date()) -> Bool {
        let monthTransactions = currentMonthTransactions(now: now)
        let reimbursementIndex = ReimbursementAllocationIndex(reimbursements)
        let items = monthTransactions.map {
            SpendItem(
                category: $0.resolvedCategory(using: rules),
                amount: reimbursementIndex.effectiveExpenseAmount(
                    transactionID: $0.id,
                    originalAmount: $0.amount
                )
            )
        }

        return WidgetSnapshotStore.publish(
            items: items,
            monthlyBudget: monthlyBudget,
            monthStart: calendar.dateInterval(of: .month, for: now)?.start ?? now,
            calendar: calendar,
            now: now,
            categoryBudgets: CategoryBudgetStore.decode(categoryBudgetsRaw),
            safeToSpendFocus: SafeToSpendFocus.categories(from: safeToSpendFocusRaw),
            isoCurrencyCode: dominantCurrency(in: monthTransactions),
            showsAmounts: showsAmounts
        )
    }

    private func currentMonthTransactions(now: Date) -> [TransactionRecord] {
        guard let interval = calendar.dateInterval(of: .month, for: now) else { return [] }
        let excluded = SpendingAccountFilter.excludedIds(from: excludedAccountsRaw)
        return transactions.filter {
            interval.containsHalfOpen($0.date)
                && SpendingAccountFilter.isIncluded($0.accountId, excluded: excluded)
        }
    }

    /// The currency the month is actually denominated in, falling back to the
    /// user's locale. The rest of the app already renders every account in one
    /// currency, so the most common code is the honest answer.
    private func dominantCurrency(in monthTransactions: [TransactionRecord]) -> String {
        let counts = Dictionary(grouping: monthTransactions.map(\.isoCurrencyCode), by: { $0 })
            .mapValues(\.count)
        if let best = counts.max(by: { $0.value < $1.value })?.key, !best.isEmpty {
            return best
        }
        return Locale.current.currency?.identifier ?? "USD"
    }
}

extension View {
    /// Keeps the widgets in step with the ledger, driven by a key that only
    /// changes on real data changes rather than on every render.
    ///
    /// Applied where the ledger is already queried. The first publish happens in
    /// `task`; after that only a change to `Key` triggers a write, and
    /// `WidgetSnapshotStore` skips the reload when the visible content matches.
    func widgetSnapshot(_ publisher: WidgetSnapshotPublisher) -> some View {
        modifier(WidgetSnapshotModifier(publisher: publisher))
    }
}

private struct WidgetSnapshotModifier: ViewModifier {
    let publisher: WidgetSnapshotPublisher
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task(id: publisher.key()) { publisher.publish() }
            // Backgrounding is the last chance to be accurate: the widget is
            // what the user reads after putting the app down.
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { publisher.publish() }
            }
    }
}
