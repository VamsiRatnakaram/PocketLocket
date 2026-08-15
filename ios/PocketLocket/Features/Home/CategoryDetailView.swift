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
    @AppStorage(SpendingAccountFilter.key) private var excludedAccountsRaw = ""
    @Environment(\.modelContext) private var context
    @State private var detail: TransactionRecord?
    @State private var isSelecting = false
    @State private var selectedTransactionIDs: Set<String> = []
    @State private var assignmentErrorMessage: String?

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

    /// Spending transactions in this category + period, most expensive first.
    private var items: [TransactionRecord] {
        let excluded = SpendingAccountFilter.excludedIds(from: excludedAccountsRaw)
        return transactions
            .filter {
                $0.amount > 0
                    && SpendingAccountFilter.isIncluded($0.accountId, excluded: excluded)
                    && $0.resolvedCategory(using: rules) == category
            }
            .sorted { $0.amount > $1.amount }
    }

    private var total: Double { items.reduce(0) { $0 + $1.amount } }

    var body: some View {
        List {
            Section {
                ForEach(items) { txn in
                    if isSelecting {
                        Button { toggleSelection(of: txn) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedTransactionIDs.contains(txn.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedTransactionIDs.contains(txn.id) ? Color.accentColor : Color.secondary)
                                TransactionRow(txn: txn, category: category)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(selectedTransactionIDs.contains(txn.id) ? "Deselect" : "Select") \(txn.title)")
                    } else {
                        Button { detail = txn } label: {
                            TransactionRow(txn: txn, category: category)
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
                    Button(allSelected ? "Deselect All" : "Select All") { toggleAll() }
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

    private var allSelected: Bool {
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

    private func toggleAll() {
        let itemIDs = Set(items.map(\.id))
        if allSelected {
            selectedTransactionIDs.subtract(itemIDs)
        } else {
            selectedTransactionIDs.formUnion(itemIDs)
        }
    }

    private func assignSelected(to destination: SpendCategory) {
        let selected = items.filter { selectedTransactionIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        do {
            try CategoryAssignment.assign(destination, to: selected, using: rules, in: context)
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
