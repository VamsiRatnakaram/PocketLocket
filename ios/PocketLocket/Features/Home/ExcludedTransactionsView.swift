import SwiftUI
import SwiftData

/// Every outflow the budget deliberately ignored this period, grouped by the
/// reason it was ignored.
///
/// The spend ring only counts `isSpending` categories, so transfers and card
/// payments vanish from it entirely. That's the right math — moving $500 from
/// checking to a credit card isn't spending $500 — but silently dropping them
/// makes a month impossible to reconcile against a statement, and hides
/// misclassifications: a Venmo that was really your half of dinner looks
/// identical to a Venmo repaying a friend, and both disappear.
///
/// Tapping a row opens the normal detail sheet, so anything filed wrongly can
/// be recategorized straight back into the budget from here.
struct ExcludedTransactionsView: View {
    let interval: DateInterval
    let periodLabel: String

    @Query private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
    @AppStorage(SpendingAccountFilter.key) private var excludedAccountsRaw = ""
    @Environment(\.dismiss) private var dismiss
    @State private var detail: TransactionRecord?

    init(interval: DateInterval, periodLabel: String) {
        self.interval = interval
        self.periodLabel = periodLabel
        let start = interval.start
        let end = interval.end
        _transactions = Query(
            filter: #Predicate<TransactionRecord> { $0.date >= start && $0.date < end },
            sort: \TransactionRecord.date,
            order: .reverse
        )
    }

    private struct Group: Identifiable {
        let category: SpendCategory
        let items: [TransactionRecord]
        var id: String { category.id }
        var total: Double { items.reduce(0) { $0 + $1.amount } }
    }

    /// Mirrors `SpendAggregator.excludedTotals`: positive (outflow) amounts in
    /// a non-spending category. Inflows are left out because they were never
    /// part of the spend total either, so listing them would only confuse the
    /// reconciliation.
    private var groups: [Group] {
        let excludedAccounts = SpendingAccountFilter.excludedIds(from: excludedAccountsRaw)
        let items = transactions.filter {
            $0.amount > 0
                && SpendingAccountFilter.isIncluded($0.accountId, excluded: excludedAccounts)
                && !$0.resolvedCategory(using: rules).isSpending
        }
        return Dictionary(grouping: items) { $0.resolvedCategory(using: rules) }
            .map { Group(category: $0.key, items: $0.value.sorted { $0.amount > $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    private var total: Double { groups.reduce(0) { $0 + $1.total } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(CurrencyFormatter.string(total))
                            .font(.largeTitle.weight(.semibold))
                            .monospacedDigit()
                        Text("left your accounts in \(periodLabel) without counting toward your budget.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                ForEach(groups) { group in
                    Section {
                        ForEach(group.items) { txn in
                            Button { detail = txn } label: {
                                TransactionRow(txn: txn, category: group.category)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Label(group.category.displayName, systemImage: group.category.symbol)
                            Spacer()
                            Text(CurrencyFormatter.string(group.total)).monospacedDigit()
                        }
                    } footer: {
                        Text(explanation(for: group.category))
                    }
                }
            }
            .navigationTitle("Not in Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $detail) { txn in
                TransactionDetailView(txn: txn, currentCategory: txn.resolvedCategory(using: rules))
            }
            .overlay {
                if groups.isEmpty {
                    ContentUnavailableView(
                        "Nothing excluded",
                        systemImage: "checkmark.circle",
                        description: Text("Every transaction in \(periodLabel) counts toward your budget.")
                    )
                }
            }
        }
    }

    private func explanation(for category: SpendCategory) -> String {
        switch category {
        case .transfer:
            return "Money moved between your own accounts, or paid toward a card. "
                + "Counting it would double up with the purchases it's paying for. "
                + "If one of these was really a purchase, tap it to recategorize."
        case .income:
            return "Money coming in. Tracked separately from spending."
        default:
            return "Excluded from the spend total."
        }
    }
}
