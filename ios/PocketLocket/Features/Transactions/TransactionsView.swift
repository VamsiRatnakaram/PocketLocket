import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Query(sort: \TransactionRecord.date, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
    @Query(sort: \AccountRecord.name) private var accounts: [AccountRecord]
    @Environment(\.modelContext) private var context

    @State private var search = ""
    @State private var accountFilter: String?
    @State private var categoryFilter: SpendCategory?
    @State private var typeFilter: TxnType = .all
    @State private var period: Period = .all
    @State private var sortOrder: SortOrder = .dateDesc
    @State private var detail: TransactionRecord?
    @State private var showAdd = false
    @State private var editing: TransactionRecord?
    @State private var isSelecting = false
    @State private var selectedTransactionIDs: Set<String> = []
    @State private var assignmentErrorMessage: String?
    @State private var rowsCache = DerivedCache<RowsKey, [TransactionListBuilder.Row]>()

    enum TxnType: String, CaseIterable, Identifiable {
        case all, expenses, income
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum Period: String, CaseIterable, Identifiable {
        case month = "This month"
        case year = "This year"
        case all = "All time"
        var id: String { rawValue }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case dateDesc = "Newest first"
        case dateAsc = "Oldest first"
        case amountDesc = "Largest first"
        case amountAsc = "Smallest first"
        var id: String { rawValue }
    }

    private var periodInterval: DateInterval? {
        let calendar = Calendar.current
        switch period {
        case .month: return calendar.dateInterval(of: .month, for: Date())
        case .year: return calendar.dateInterval(of: .year, for: Date())
        case .all: return nil
        }
    }

    private func category(for txn: TransactionRecord) -> SpendCategory {
        txn.resolvedCategory(using: rules)
    }

    private func delete(_ txn: TransactionRecord) {
        context.delete(txn)
        try? context.save()
    }

    private var hasActiveFilters: Bool {
        accountFilter != nil || categoryFilter != nil || typeFilter != .all || period != .all
    }

    private var criteria: TransactionListBuilder.Criteria {
        TransactionListBuilder.Criteria(
            search: search,
            accountId: accountFilter,
            category: categoryFilter,
            type: typeFilter,
            periodInterval: periodInterval,
            sortOrder: sortOrder
        )
    }

    private struct RowsKey: Equatable {
        var criteria: TransactionListBuilder.Criteria
        var dataHash: Int
        var rulesHash: Int
    }

    /// The visible list, rebuilt only when the data or the criteria change.
    ///
    /// `body` needs this in half a dozen places — the `ForEach`, two toolbar
    /// `isEmpty` checks, the select-all state, the empty-state overlay, the
    /// animation trigger — and as a plain computed property every one of those
    /// re-ran the whole filter and sort over every transaction on file. The
    /// cache collapses them into a single pass.
    private var rows: [TransactionListBuilder.Row] {
        let key = RowsKey(
            criteria: criteria,
            dataHash: RecordHash.transactions(transactions),
            rulesHash: RecordHash.rules(rules)
        )
        return rowsCache.value(for: key) {
            TransactionListBuilder.rows(from: transactions, criteria: criteria) {
                $0.resolvedCategory(using: rules)
            }
        }
    }

    var body: some View {
        // Read once and thread it through: every reference to `rows` pays for the
        // content hash that keys the cache, so reading it per call site would
        // just trade six filter passes for six hashing passes.
        content(rows: rows)
    }

    private func content(rows: [TransactionListBuilder.Row]) -> some View {
        NavigationStack {
            List {
                ForEach(rows) { row in
                    let txn = row.transaction
                    if isSelecting {
                        Button { toggleSelection(of: txn) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedTransactionIDs.contains(txn.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedTransactionIDs.contains(txn.id) ? Color.accentColor : Color.secondary)
                                TransactionRow(txn: txn, category: row.category)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(selectedTransactionIDs.contains(txn.id) ? "Deselect" : "Select") \(txn.title)")
                    } else {
                        Button { detail = txn } label: {
                            TransactionRow(txn: txn, category: row.category)
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                        .swipeActions(edge: .trailing) {
                            if txn.plaidTransactionId.hasPrefix("manual-") {
                                Button(role: .destructive) { delete(txn) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button { editing = txn } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Transactions")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search merchants")
            .safeAreaInset(edge: .top) {
                if !isSelecting { typeBar }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting { selectionBar }
            }
            .toolbar {
                if isSelecting {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { endSelection() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(allVisibleSelected(in: rows) ? "Deselect All" : "Select All") { toggleAllVisible(rows) }
                            .disabled(rows.isEmpty)
                    }
                } else {
                    filterMenu
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { isSelecting = true } label: {
                            Image(systemName: "checklist")
                        }
                        .accessibilityLabel("Select transactions")
                        .disabled(rows.isEmpty)
                    }
                }
            }
            .sheet(item: $detail) { txn in
                TransactionDetailView(txn: txn, currentCategory: category(for: txn))
            }
            .sheet(isPresented: $showAdd) { ManualTransactionView() }
            .sheet(item: $editing) { txn in ManualTransactionView(editing: txn) }
            .alert("Couldn’t Assign Category", isPresented: assignmentErrorBinding) {
                Button("OK", role: .cancel) { assignmentErrorMessage = nil }
            } message: {
                Text(assignmentErrorMessage ?? "Please try again.")
            }
            .animation(.default, value: rows.count)
            .overlay {
                if transactions.isEmpty {
                    ContentUnavailableView(
                        "No transactions",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Connect a bank account to see your spending here.")
                    )
                } else if rows.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
    }

    private func allVisibleSelected(in rows: [TransactionListBuilder.Row]) -> Bool {
        !rows.isEmpty && rows.allSatisfy { selectedTransactionIDs.contains($0.id) }
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Text("\(selectedTransactionIDs.count) selected")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Spacer()
            Menu {
                ForEach(SpendCategory.allCases) { category in
                    Button { assignSelected(to: category) } label: {
                        Label(category.displayName, systemImage: category.symbol)
                    }
                }
            } label: {
                Label("Assign Category", systemImage: "tag.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedTransactionIDs.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var typeBar: some View {
        Picker("Type", selection: $typeFilter) {
            ForEach(TxnType.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
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

    private func toggleAllVisible(_ rows: [TransactionListBuilder.Row]) {
        let visibleIDs = Set(rows.map(\.id))
        if allVisibleSelected(in: rows) {
            selectedTransactionIDs.subtract(visibleIDs)
        } else {
            selectedTransactionIDs.formUnion(visibleIDs)
        }
    }

    private func assignSelected(to category: SpendCategory) {
        let selected = transactions.filter { selectedTransactionIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        do {
            try CategoryAssignment.assign(category, to: selected, using: rules, in: context)
            endSelection()
        } catch {
            assignmentErrorMessage = error.localizedDescription
        }
    }

    private func endSelection() {
        selectedTransactionIDs.removeAll()
        isSelecting = false
    }

    @ToolbarContentBuilder
    private var filterMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Menu("Account") {
                    Button { accountFilter = nil } label: {
                        Label("All accounts", systemImage: accountFilter == nil ? "checkmark" : "tray.full")
                    }
                    ForEach(accounts) { account in
                        Button { accountFilter = account.id } label: {
                            Label(account.displayName, systemImage: accountFilter == account.id ? "checkmark" : "creditcard")
                        }
                    }
                }
                Menu("Category") {
                    Button { categoryFilter = nil } label: {
                        Label("All categories", systemImage: categoryFilter == nil ? "checkmark" : "square.grid.2x2")
                    }
                    ForEach(SpendCategory.allCases) { cat in
                        Button { categoryFilter = cat } label: {
                            Label(cat.displayName, systemImage: categoryFilter == cat ? "checkmark" : cat.symbol)
                        }
                    }
                }
                Menu("Period") {
                    ForEach(Period.allCases) { option in
                        Button { period = option } label: {
                            Label(option.rawValue, systemImage: period == option ? "checkmark" : "calendar")
                        }
                    }
                }
                // An inline Picker, not Buttons: it draws the system's own
                // selection checkmark. Swapping each option's icon for a
                // checkmark when selected meant the icon column carried two
                // different meanings at once, and the arrows it swapped out
                // read as directions rather than as sort orders.
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.inline)
                if hasActiveFilters {
                    Divider()
                    Button(role: .destructive) {
                        accountFilter = nil
                        categoryFilter = nil
                        typeFilter = .all
                        period = .all
                    } label: {
                        Label("Clear filters", systemImage: "xmark.circle")
                    }
                }
            } label: {
                Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
        }
    }
}
