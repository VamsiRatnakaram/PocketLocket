import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Query(sort: \TransactionRecord.date, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
    @Query private var reimbursementAllocations: [ReimbursementAllocation]
    @Query(sort: \AccountRecord.name) private var accounts: [AccountRecord]
    @Environment(\.modelContext) private var context

    @AppStorage(SpendingAccountFilter.key) private var excludedAccountsRaw = ""

    @State private var search = ""
    @State private var accountFilter: String?
    @State private var categoryFilter: SpendCategory?
    @State private var typeFilter: TxnType = .all
    @State private var budgetFilter: BudgetFilter = .all
    @State private var period: Period = .all
    @State private var sortOrder: SortOrder = .dateDesc
    @State private var detail: TransactionRecord?
    @State private var showAdd = false
    @State private var editing: TransactionRecord?
    @State private var isSelecting = false
    @State private var isRefreshing = false
    @State private var selectedTransactionIDs: Set<String> = []
    @State private var assignmentErrorMessage: String?
    @State private var syncErrorMessage: String?
    @State private var rowsCache = DerivedCache<RowsKey, [TransactionListBuilder.Row]>()

    enum TxnType: String, CaseIterable, Identifiable {
        case all, expenses, returns, income
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    /// Lets you isolate the outflows the budget ignores. Transfers and card
    /// payments are excluded from the spend ring but look identical to
    /// everything else in this list, so there was no way to review what the
    /// app had quietly set aside — or to spot a purchase misfiled as a
    /// transfer.
    enum BudgetFilter: String, CaseIterable, Identifiable {
        case all = "All transactions"
        case counted = "In budget"
        case excluded = "Not in budget"
        var id: String { rawValue }
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

    private func accountLabel(for txn: TransactionRecord) -> String? {
        guard let accountID = txn.accountId,
              let account = accounts.first(where: { $0.id == accountID })
        else { return nil }
        let name = account.displayName
        guard let mask = account.mask,
              !mask.isEmpty,
              !name.localizedCaseInsensitiveContains(mask)
        else { return name }
        return "\(name) ••••\(mask)"
    }

    private func delete(_ txn: TransactionRecord) {
        ReimbursementAllocationService.deleteAllocations(
            referencing: [txn.id],
            from: reimbursementAllocations,
            in: context
        )
        context.delete(txn)
        try? context.save()
    }

    /// Pull-to-refresh, matching Home and Accounts. Skipped while multi-select
    /// is active so a sync can't shift rows under an in-progress selection.
    private func refresh() async {
        guard !isSelecting else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await SyncService.shared.refresh(context: context)
        } catch is CancellationError {
            // A superseded/cancelled refresh (e.g. the pull gesture resetting) is benign.
        } catch let error as URLError where error.code == .cancelled {
            // Benign cancellation — the next pull will refresh.
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    private var hasActiveFilters: Bool {
        accountFilter != nil || categoryFilter != nil || typeFilter != .all || period != .all
            || budgetFilter != .all
    }

    private var excludedAccountIds: Set<String> {
        SpendingAccountFilter.excludedIds(from: excludedAccountsRaw)
    }

    private var criteria: TransactionListBuilder.Criteria {
        TransactionListBuilder.Criteria(
            search: search,
            accountId: accountFilter,
            category: categoryFilter,
            type: typeFilter,
            budget: budgetFilter,
            periodInterval: periodInterval,
            sortOrder: sortOrder,
            excludedAccountIds: excludedAccountIds
        )
    }

    private struct RowsKey: Equatable {
        var criteria: TransactionListBuilder.Criteria
        var dataHash: Int
        var rulesHash: Int
        var reimbursementsHash: Int
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
            rulesHash: RecordHash.rules(rules),
            reimbursementsHash: RecordHash.reimbursements(reimbursementAllocations)
        )
        return rowsCache.value(for: key) {
            TransactionListBuilder.rows(
                from: transactions,
                criteria: criteria,
                reimbursementIndex: ReimbursementAllocationIndex(reimbursementAllocations)
            ) {
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
                                TransactionRow(
                                    txn: txn,
                                    category: row.category,
                                    reimbursedAmount: row.reimbursedAmount,
                                    reimbursementSourceAmount: row.reimbursementSourceAmount,
                                    accountLabel: accountLabel(for: txn)
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
                                category: row.category,
                                reimbursedAmount: row.reimbursedAmount,
                                reimbursementSourceAmount: row.reimbursementSourceAmount,
                                accountLabel: accountLabel(for: txn)
                            )
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
            .refreshable { await refresh() }
            .navigationTitle("Transactions")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search merchants")
            .adaptiveSafeAreaBar(edge: .top) {
                if !isSelecting { typeBar }
            }
            .adaptiveSafeAreaBar(edge: .bottom) {
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
                        // The guard in `refresh()` only stops a sync starting
                        // during a selection. Entering a selection during a
                        // sync let rows shift underneath it just the same, so
                        // selected transactions could vanish before the bulk
                        // assignment ran.
                        Button { isSelecting = true } label: {
                            Image(systemName: "checklist")
                        }
                        .accessibilityLabel("Select transactions")
                        .disabled(isRefreshing || rows.isEmpty)
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
            .alert("Couldn’t Refresh", isPresented: syncErrorBinding) {
                Button("OK", role: .cancel) { syncErrorMessage = nil }
            } message: {
                Text(syncErrorMessage ?? "Please try again.")
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
            .adaptiveProminentButtonStyle()
            .disabled(selectedTransactionIDs.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .legacyBarBackground()
    }

    private var typeBar: some View {
        VStack(spacing: 4) {
            Picker("Type", selection: $typeFilter) {
                ForEach(TxnType.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if typeFilter == .returns {
                Text(
                    "Money received from a spending merchant—or labeled "
                        + "refund, return, or reversal. Peer-to-peer payments stay Income."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .legacyBarBackground()
        .animation(.easeInOut(duration: 0.15), value: typeFilter)
    }

    private var assignmentErrorBinding: Binding<Bool> {
        Binding(
            get: { assignmentErrorMessage != nil },
            set: { if !$0 { assignmentErrorMessage = nil } }
        )
    }

    private var syncErrorBinding: Binding<Bool> {
        Binding(
            get: { syncErrorMessage != nil },
            set: { if !$0 { syncErrorMessage = nil } }
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
            try CategoryAssignment.assign(
                category, to: selected, using: rules, in: context, ledger: transactions
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

    @ToolbarContentBuilder
    private var filterMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                // Each filter is a submenu wrapping an inline Picker.
                //
                // A bare Picker in a Menu is not reliably collapsed — it draws
                // its options expanded in place, so opening the filter gave one
                // long splayed-out list of every account, category and period
                // at once. Nesting the Menu guarantees a single compact row per
                // filter, and the inline Picker inside it keeps the system's
                // own selection checkmark rather than swapping an option's icon
                // for one.
                Menu("Account") {
                    Picker("Account", selection: $accountFilter) {
                        Text("All accounts").tag(String?.none)
                        ForEach(accounts) { account in
                            Text(account.displayName).tag(String?.some(account.id))
                        }
                    }
                    .pickerStyle(.inline)
                }
                Menu("Category") {
                    Picker("Category", selection: $categoryFilter) {
                        Text("All categories").tag(SpendCategory?.none)
                        ForEach(SpendCategory.allCases) { cat in
                            Label(cat.displayName, systemImage: cat.symbol).tag(SpendCategory?.some(cat))
                        }
                    }
                    .pickerStyle(.inline)
                }
                Menu("Budget") {
                    Picker("Budget", selection: $budgetFilter) {
                        ForEach(BudgetFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                }
                Menu("Period") {
                    Picker("Period", selection: $period) {
                        ForEach(Period.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                }
                // The arrows this replaced read as directions rather than as
                // sort orders, so options are text-only here.
                Menu("Sort") {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(SortOrder.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                }
                if hasActiveFilters {
                    Divider()
                    Button(role: .destructive) {
                        accountFilter = nil
                        categoryFilter = nil
                        typeFilter = .all
                        period = .all
                        budgetFilter = .all
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
