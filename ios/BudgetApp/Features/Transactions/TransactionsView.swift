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
    }

    private var filtered: [TransactionRecord] {
        transactions.filter { txn in
            if let periodInterval, !periodInterval.contains(txn.date) { return false }
            if let accountFilter, txn.accountId != accountFilter { return false }
            if let categoryFilter, category(for: txn) != categoryFilter { return false }
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
            .listStyle(.plain)
            .navigationTitle("Transactions")
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search merchants")
            .safeAreaInset(edge: .top) { typeBar }
            .toolbar {
                filterMenu
                ToolbarItem(placement: .topBarLeading) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $detail) { txn in
                TransactionDetailView(txn: txn, currentCategory: category(for: txn))
            }
            .sheet(isPresented: $showAdd) { ManualTransactionView() }
            .sheet(item: $editing) { txn in ManualTransactionView(editing: txn) }
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

    private var typeBar: some View {
        Picker("Type", selection: $typeFilter) {
            ForEach(TxnType.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
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
