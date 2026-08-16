import SwiftUI
import SwiftData

/// Drill-down for a single category: every transaction in that category for the
/// selected period, sorted from most to least expensive.
struct CategoryDetailView: View {
    let category: SpendCategory
    let interval: DateInterval
    let periodLabel: String

    @Query private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
    @Query private var reimbursementAllocations: [ReimbursementAllocation]
    @AppStorage(SpendingAccountFilter.key) private var excludedAccountsRaw = ""
    @Environment(\.modelContext) private var context
    @State private var detail: TransactionRecord?
    @State private var isSelecting = false
    @State private var selectedTransactionIDs: Set<String> = []
    @State private var assignmentErrorMessage: String?
    @State private var itemsCache = DerivedCache<ItemsKey, [TransactionRecord]>()

    init(category: SpendCategory, interval: DateInterval, periodLabel: String) {
        self.category = category
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

    private struct ItemsKey: Equatable {
        var dataHash: Int
        var rulesHash: Int
        var reimbursementsHash: Int
        var category: SpendCategory
        var excludedAccountsRaw: String
    }

    /// Spending transactions in this category + period, most expensive first.
    ///
    /// Seven places in `body` need this — the rows, the header count, two
    /// toolbar `isEmpty` checks, the empty-state overlay, select-all, and the
    /// total — and recomputing it at each one meant filtering, resolving a
    /// category per transaction, and re-sorting seven times per render.
    private var items: [TransactionRecord] {
        let key = ItemsKey(
            dataHash: RecordHash.transactions(transactions),
            rulesHash: RecordHash.rules(rules),
            reimbursementsHash: RecordHash.reimbursements(reimbursementAllocations),
            category: category,
            excludedAccountsRaw: excludedAccountsRaw
        )
        return itemsCache.value(for: key) {
            let reimbursementIndex = ReimbursementAllocationIndex(reimbursementAllocations)
            let excluded = SpendingAccountFilter.excludedIds(from: excludedAccountsRaw)
            return transactions
                .filter {
                    $0.amount > 0
                        && SpendingAccountFilter.isIncluded($0.accountId, excluded: excluded)
                        && $0.resolvedCategory(using: rules) == category
                }
                .sorted {
                    reimbursementIndex.effectiveExpenseAmount(
                        transactionID: $0.id, originalAmount: $0.amount
                    ) > reimbursementIndex.effectiveExpenseAmount(
                        transactionID: $1.id, originalAmount: $1.amount
                    )
                }
        }
    }

    var body: some View {
        content(items)
    }

    private func content(_ items: [TransactionRecord]) -> some View {
        let reimbursementIndex = ReimbursementAllocationIndex(reimbursementAllocations)
        let total = items.reduce(0) {
            $0 + reimbursementIndex.effectiveExpenseAmount(
                transactionID: $1.id,
                originalAmount: $1.amount
            )
        }
        return List {
            Section {
                ForEach(items) { txn in
                    if isSelecting {
                        Button { toggleSelection(of: txn) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedTransactionIDs.contains(txn.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedTransactionIDs.contains(txn.id) ? Color.accentColor : Color.secondary)
                                TransactionRow(
                                    txn: txn,
                                    category: category,
                                    reimbursedAmount: reimbursementIndex.allocatedToExpense(txn.id)
                                )
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(selectedTransactionIDs.contains(txn.id) ? "Deselect" : "Select") \(txn.title)")
                    } else {
                        Button { detail = txn } label: {
                            TransactionRow(
                                txn: txn,
                                category: category,
                                reimbursedAmount: reimbursementIndex.allocatedToExpense(txn.id)
                            )
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                    }
                }
            } header: {
                HStack {
                    Text(periodLabel)
                    Spacer()
                    Text("\(items.count) • \(CurrencyFormatter.string(total))")
                        .monospacedDigit()
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .adaptiveSafeAreaBar(edge: .bottom) {
            if isSelecting { selectionBar }
        }
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { endSelection() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(allSelected(in: items) ? "Deselect All" : "Select All") { toggleAll(items) }
                        .disabled(items.isEmpty)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Select") { isSelecting = true }
                        .disabled(items.isEmpty)
                }
            }
        }
        .sheet(item: $detail) { txn in
            TransactionDetailView(txn: txn, currentCategory: category)
        }
        .alert("Couldn’t Assign Category", isPresented: assignmentErrorBinding) {
            Button("OK", role: .cancel) { assignmentErrorMessage = nil }
        } message: {
            Text(assignmentErrorMessage ?? "Please try again.")
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "Nothing here",
                    systemImage: category.symbol,
                    description: Text("No \(category.displayName) spending in \(periodLabel).")
                )
            }
        }
    }

    private func allSelected(in items: [TransactionRecord]) -> Bool {
        !items.isEmpty && items.allSatisfy { selectedTransactionIDs.contains($0.id) }
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Text("\(selectedTransactionIDs.count) selected")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Spacer()
            Menu {
                ForEach(SpendCategory.allCases.filter { $0 != category }) { destination in
                    Button { assignSelected(to: destination) } label: {
                        Label(destination.displayName, systemImage: destination.symbol)
                    }
                }
            } label: {
                Label("Move to Category", systemImage: "tag.fill")
            }
            .adaptiveProminentButtonStyle()
            .disabled(selectedTransactionIDs.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .legacyBarBackground()
    }

    private var assignmentErrorBinding: Binding<Bool> {
        Binding(
            get: { assignmentErrorMessage != nil },
            set: { if !$0 { assignmentErrorMessage = nil } }
        )
    }

    private func toggleSelection(of transaction: TransactionRecord) {
        if selectedTransactionIDs.contains(transaction.id) {
            selectedTransactionIDs.remove(transaction.id)
        } else {
            selectedTransactionIDs.insert(transaction.id)
        }
    }

    private func toggleAll(_ items: [TransactionRecord]) {
        let itemIDs = Set(items.map(\.id))
        if allSelected(in: items) {
            selectedTransactionIDs.subtract(itemIDs)
        } else {
            selectedTransactionIDs.formUnion(itemIDs)
        }
    }

    private func assignSelected(to destination: SpendCategory) {
        let selected = items.filter { selectedTransactionIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        do {
            try CategoryAssignment.assign(
                destination, to: selected, using: rules, in: context, ledger: transactions
            )
            endSelection()
        } catch {
            assignmentErrorMessage = error.localizedDescription
        }
    }

    private func endSelection() {
        selectedTransactionIDs.removeAll()
        isSelecting = false
    }
}
