import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Query(sort: \TransactionRecord.date, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
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
    @State private var selectedTransactionIDs: Set<String> = []
    @State private var assignmentErrorMessage: String?

    enum TxnType: String, CaseIterable, Identifiable {
        case all, expenses, income
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
        var symbol: String {
            switch self {
            case .all: return "tray.full"
            case .counted: return "checkmark.circle"
            case .excluded: return "minus.circle"
            }
        }
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
        var symbol: String {
            switch self {
            case .dateDesc: return "arrow.down"
            case .dateAsc: return "arrow.up"
            case .amountDesc: return "arrow.down.circle"
            case .amountAsc: return "arrow.up.circle"
            }
        }
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
            || budgetFilter != .all
    }

    private var excludedAccountIds: Set<String> {
        SpendingAccountFilter.excludedIds(from: excludedAccountsRaw)
    }

    private var filtered: [TransactionRecord] {
        transactions.filter { txn in
            if let periodInterval, !periodInterval.containsHalfOpen(txn.date) { return false }
            if let accountFilter, txn.accountId != accountFilter { return false }
            if let categoryFilter, category(for: txn) != categoryFilter { return false }
            switch budgetFilter {
            case .all: break
            case .counted:
                if !SpendingAccountFilter.countsTowardBudget(
                    category: category(for: txn), amount: txn.amount,
                    accountId: txn.accountId, excluded: excludedAccountIds
                ) { return false }
            case .excluded:
                if SpendingAccountFilter.countsTowardBudget(
                    category: category(for: txn), amount: txn.amount,
                    accountId: txn.accountId, excluded: excludedAccountIds
                ) { return false }
            }
            switch typeFilter {
            case .all: break
            case .expenses: if txn.amount <= 0 { return false }
            case .income: if txn.amount >= 0 { return false }
            }
            if !search.isEmpty {
                return txn.title.localizedCaseInsensitiveContains(search)
                    || txn.name.localizedCaseInsensitiveContains(search)
            }
            return true
        }
    }

    private var sortedFiltered: [TransactionRecord] {
        switch sortOrder {
        case .dateDesc: return filtered.sorted { $0.date > $1.date }
        case .dateAsc: return filtered.sorted { $0.date < $1.date }
        case .amountDesc: return filtered.sorted { $0.amount > $1.amount }
        case .amountAsc: return filtered.sorted { $0.amount < $1.amount }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedFiltered) { txn in
                    if isSelecting {
                        Button { toggleSelection(of: txn) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedTransactionIDs.contains(txn.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedTransactionIDs.contains(txn.id) ? Color.accentColor : Color.secondary)
                                TransactionRow(txn: txn, category: category(for: txn))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(selectedTransactionIDs.contains(txn.id) ? "Deselect" : "Select") \(txn.title)")
                    } else {
                        Button { detail = txn } label: {
                            TransactionRow(txn: txn, category: category(for: txn))
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
                        Button(allVisibleSelected ? "Deselect All" : "Select All") { toggleAllVisible() }
                            .disabled(sortedFiltered.isEmpty)
                    }
                } else {
                    filterMenu
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Select") { isSelecting = true }
                            .disabled(sortedFiltered.isEmpty)
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
            .animation(.default, value: filtered.count)
            .overlay {
                if transactions.isEmpty {
                    ContentUnavailableView(
                        "No transactions",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Connect a bank account to see your spending here.")
                    )
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
    }

    private var allVisibleSelected: Bool {
        !sortedFiltered.isEmpty && sortedFiltered.allSatisfy { selectedTransactionIDs.contains($0.id) }
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

    private func toggleAllVisible() {
        let visibleIDs = Set(sortedFiltered.map(\.id))
        if allVisibleSelected {
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
                Menu("Budget") {
                    ForEach(BudgetFilter.allCases) { option in
                        Button { budgetFilter = option } label: {
                            Label(option.rawValue, systemImage: budgetFilter == option ? "checkmark" : option.symbol)
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
                Menu("Sort") {
                    ForEach(SortOrder.allCases) { option in
                        Button { sortOrder = option } label: {
                            Label(option.rawValue, systemImage: sortOrder == option ? "checkmark" : option.symbol)
                        }
                    }
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
