import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \TransactionRecord.date, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]

    @AppStorage("monthlyBudget") private var monthlyBudget: Double = 3000
    @AppStorage("ringStyle") private var ringStyleRaw: String = RingStyle.donut.rawValue
    @AppStorage(SpendingAccountFilter.key) private var excludedAccountsRaw = ""
    @AppStorage(SafeToSpendFocus.key) private var safeToSpendFocusRaw = ""
    @AppStorage(CategoryBudgetStore.key) private var categoryBudgetsRaw = ""

    @State private var isSyncing = false
    @State private var showSimpleFIN = false
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var importMessage: String?
    @State private var errorMessage: String?
    @State private var refreshTick = 0
    @State private var monthOffset = 0
    @State private var scope: Scope = .month
    @State private var selectedCategory: SpendCategory?
    @State private var summaryCache = DerivedCache<MonthKey, MonthSummary>()

    enum Scope: Hashable { case month, year }

    private var ringStyle: RingStyle { RingStyle(rawValue: ringStyleRaw) ?? .donut }

    /// The calendar month being viewed (0 = this month, -1 = last month, …).
    private var monthDate: Date {
        Calendar.current.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }

    private var monthInterval: DateInterval {
        Calendar.current.dateInterval(of: .month, for: monthDate)
            ?? DateInterval(start: monthDate, duration: 0)
    }

    /// The furthest month back that actually has data (0 = this month).
    private var minMonthOffset: Int {
        guard let earliest = transactions.map(\.date).min() else { return 0 }
        let calendar = Calendar.current
        guard
            let currentStart = calendar.dateInterval(of: .month, for: Date())?.start,
            let earliestStart = calendar.dateInterval(of: .month, for: earliest)?.start
        else { return 0 }
        return calendar.dateComponents([.month], from: currentStart, to: earliestStart).month ?? 0
    }

    private var excludedAccountIds: Set<String> {
        SpendingAccountFilter.excludedIds(from: excludedAccountsRaw)
    }

    /// Everything the month view derives from the ledger, computed in one pass.
    ///
    /// `items` carries each transaction's resolved category, so Safe-to-spend
    /// can reuse it instead of resolving the month a second time.
    private struct MonthSummary {
        let items: [SpendItem]
        let viewModel: HomeViewModel
    }

    private struct MonthKey: Equatable {
        var dataHash: Int
        var rulesHash: Int
        var monthStart: Date
        var excludedAccountsRaw: String
        var monthlyBudget: Double
    }

    /// The month's totals, rebuilt only when the ledger, the rules, the
    /// selected month, the account filter or the budget actually change.
    ///
    /// `body` reaches for this a dozen times — the ring, the breakdown list,
    /// the remaining/over-budget label, Safe-to-spend — and as a plain computed
    /// property each of those re-filtered every transaction on file, resolved a
    /// category for each survivor, and re-ran both aggregation passes.
    private var summary: MonthSummary {
        // Narrow to the month with cheap scalar comparisons *before* hashing.
        // Home only ever shows one month, so hashing the entire ledger to key
        // the cache would cost more than the work it protects.
        let excluded = excludedAccountIds
        let monthTransactions = transactions.filter {
            monthInterval.contains($0.date)
                && SpendingAccountFilter.isIncluded($0.accountId, excluded: excluded)
        }
        let key = MonthKey(
            dataHash: RecordHash.transactions(monthTransactions),
            rulesHash: RecordHash.rules(rules),
            monthStart: monthInterval.start,
            excludedAccountsRaw: excludedAccountsRaw,
            monthlyBudget: monthlyBudget
        )
        return summaryCache.value(for: key) {
            let items = monthTransactions.map {
                SpendItem(category: $0.resolvedCategory(using: rules), amount: $0.amount)
            }
            return MonthSummary(
                items: items,
                viewModel: HomeViewModel(items: items, monthlyBudget: monthlyBudget)
            )
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $scope) {
                    Text("Month").tag(Scope.month)
                    Text("Year").tag(Scope.year)
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                switch scope {
                case .month: monthContent(summary)
                case .year: YearOverviewView { year, monthIndex in
                    showMonth(year: year, monthIndex: monthIndex)
                }
                }
            }
            .navigationTitle("Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showSimpleFIN) {
                SimpleFINConnectView { Task { await refresh() } }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: ImportService.allowedTypes) { result in
                handleImport(result)
            }
            .alert("Import", isPresented: importAlertBinding) {
                Button("OK", role: .cancel) { importMessage = nil }
            } message: { Text(importMessage ?? "") }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .overlay {
                if isSyncing && transactions.isEmpty {
                    ProgressView("Syncing…")
                }
            }
            .sensoryFeedback(.impact, trigger: refreshTick)
        }
    }

    private func monthContent(_ summary: MonthSummary) -> some View {
        let viewModel = summary.viewModel
        return
        ScrollView {
            VStack(spacing: 28) {
                monthSwitcher
                ringSection(viewModel)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: monthOffset)
                remainingLabel(summary)

                if viewModel.spends.isEmpty {
                    emptyState
                } else {
                    CategoryBreakdownList(spends: viewModel.spends, total: viewModel.totalSpent, interval: monthInterval, periodLabel: monthTitle, showBudgets: true)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .refreshable { await refresh() }
        .simultaneousGesture(monthSwipeGesture)
        .navigationDestination(item: $selectedCategory) { category in
            CategoryDetailView(category: category, interval: monthInterval, periodLabel: monthTitle)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func ringSection(_ viewModel: HomeViewModel) -> some View {
        switch ringStyle {
        case .donut:
            SpendRingView(
                spends: viewModel.spends,
                totalSpent: viewModel.totalSpent,
                monthlyBudget: monthlyBudget
            ) { category in
                selectedCategory = category
            }
        case .progress:
            SpendRingProgress(totalSpent: viewModel.totalSpent, monthlyBudget: monthlyBudget)
        }
    }

    private var daysLeftInMonth: Int {
        let calendar = Calendar.current
        let now = Date()
        guard let range = calendar.range(of: .day, in: .month, for: now) else { return 1 }
        return max(1, range.count - calendar.component(.day, from: now) + 1)
    }

    /// Budget basis, spent, and a label for Safe-to-spend: category-focused when
    /// categories are starred and budgeted, otherwise the overall monthly budget.
    private func safeToSpendBasis(_ summary: MonthSummary) -> (budget: Double, spent: Double, label: String)? {
        let budgets = CategoryBudgetStore.decode(categoryBudgetsRaw)
        let focus = SafeToSpendFocus.categories(from: safeToSpendFocusRaw).filter { budgets[$0] != nil }
        if !focus.isEmpty {
            let budget = focus.reduce(0) { $0 + (budgets[$1] ?? 0) }
            // Reuses the categories resolved for the summary rather than
            // resolving the whole month again.
            let spent = summary.items
                .filter { $0.amount > 0 && focus.contains($0.category) }
                .reduce(0) { $0 + $1.amount }
            let names = focus.map(\.displayName).sorted().joined(separator: ", ")
            return (budget, spent, names)
        } else if monthlyBudget > 0 {
            return (monthlyBudget, summary.viewModel.totalSpent, "")
        }
        return nil
    }

    private func safeToSpend(_ basis: (budget: Double, spent: Double, label: String)?) -> Double {
        guard let basis else { return 0 }
        return max(0, basis.budget - basis.spent) / Double(daysLeftInMonth)
    }

    private func safeToSpendLabel(_ basis: (budget: Double, spent: Double, label: String)?) -> String {
        let amount = CurrencyFormatter.string(safeToSpend(basis))
        if let basis, !basis.label.isEmpty {
            return "\(basis.label): \(amount)/day"
        }
        return "Safe to spend today: \(amount)"
    }

    private func remainingLabel(_ summary: MonthSummary) -> some View {
        let viewModel = summary.viewModel
        return
        VStack(spacing: 4) {
            if viewModel.isOverBudget {
                Text("\(CurrencyFormatter.string(-viewModel.remaining)) over budget")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red)
            } else if monthOffset == 0 {
                Text("\(CurrencyFormatter.string(viewModel.remaining)) left this month")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(safeToSpendLabel(safeToSpendBasis(summary)))
                    .font(.caption)
                    .foregroundStyle(.tint)
            } else {
                Text("\(CurrencyFormatter.string(viewModel.totalSpent)) spent")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if transactions.isEmpty {
            ContentUnavailableView {
                Label("No spending yet", systemImage: "chart.pie")
            } description: {
                Text("Connect a bank account to see your spending broken down by category.")
            } actions: {
                Button("Connect an account") { showSimpleFIN = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        } else {
            ContentUnavailableView {
                Label("No spending in \(monthTitle)", systemImage: "calendar")
            } description: {
                Text("Use the arrows above to browse another month.")
            }
            .padding(.top, 8)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Ring style", selection: $ringStyleRaw) {
                    ForEach(RingStyle.allCases) { style in
                        Label(style.label, systemImage: style.symbol).tag(style.rawValue)
                    }
                }
            } label: {
                Image(systemName: "circle.dashed")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showSimpleFIN = true } label: { Label("Auto-sync (SimpleFIN)", systemImage: "arrow.triangle.2.circlepath") }
                Button { showImporter = true } label: { Label("Import statement (free)", systemImage: "square.and.arrow.down") }
            } label: {
                Image(systemName: "plus.circle")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { Task { await refresh() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isSyncing)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
        }
    }

    // MARK: - Actions

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var monthTitle: String {
        monthDate.formatted(.dateTime.month(.wide).year())
    }

    private var monthSwitcher: some View {
        HStack {
            Button { moveMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .disabled(monthOffset <= minMonthOffset)
            .opacity(monthOffset <= minMonthOffset ? 0.25 : 1)
            Spacer()
            Text(monthTitle)
                .font(.system(.title, design: .rounded).weight(.bold))
                .contentTransition(.numericText())
            Spacer()
            Button { moveMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .disabled(monthOffset >= 0)
            .opacity(monthOffset >= 0 ? 0.25 : 1)
        }
        .padding(.horizontal)
    }

    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.predictedEndTranslation.width
                let vertical = value.predictedEndTranslation.height
                guard abs(horizontal) > 60, abs(horizontal) > abs(vertical) * 1.4 else { return }
                moveMonth(by: horizontal < 0 ? 1 : -1)
            }
    }

    private func moveMonth(by delta: Int) {
        let target = min(0, max(minMonthOffset, monthOffset + delta))
        guard target != monthOffset else { return }
        withAnimation(reduceMotion ? nil : .snappy) { monthOffset = target }
    }

    private func showMonth(year: Int, monthIndex: Int) {
        let calendar = Calendar.current
        guard
            let target = calendar.date(from: DateComponents(year: year, month: monthIndex + 1)),
            let currentStart = calendar.dateInterval(of: .month, for: Date())?.start,
            let targetStart = calendar.dateInterval(of: .month, for: target)?.start
        else { return }
        let months = calendar.dateComponents([.month], from: currentStart, to: targetStart).month ?? 0
        withAnimation(reduceMotion ? nil : .smooth) {
            monthOffset = months
            scope = .month
        }
    }

    private func refresh() async {
        refreshTick += 1
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await SyncService.shared.refresh(context: context)
        } catch is CancellationError {
            // A superseded/cancelled refresh (e.g. the pull gesture reset on Mac) is benign.
        } catch let error as URLError where error.code == .cancelled {
            // Benign cancellation — nothing failed; the Sync button or next pull will refresh.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var importAlertBinding: Binding<Bool> {
        Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let count = try ImportService.importFile(at: url, into: context)
                importMessage = "Imported \(count) transaction\(count == 1 ? "" : "s")."
            } catch {
                importMessage = "Couldn't import: \(error.localizedDescription)"
            }
        case .failure(let error):
            importMessage = error.localizedDescription
        }
    }
}
