import SwiftUI
import SwiftData
import Charts

/// Mines transaction history for merchant frequency, spend habits, and
/// category trends — "how many times have I eaten here", "average grocery
/// spend", "businesses I frequent" — computed entirely on-device.
struct AnalysisView: View {
    var isActive = true

    @AppStorage(SpendingAccountFilter.key) private var excludedAccountsRaw = ""

    @State private var range: AnalysisTimeRange = .twelveMonths
    @State private var availableRanges = AnalysisTimeRange.allCases
    @State private var selectedMerchant: MerchantAnalytics.MerchantStats?
    @State private var selectedCategory: SpendCategory?
    @State private var categoryFilter: SpendCategory?
    /// Categories tapped "off" in the chart legend, per Vamsi's feedback that
    /// the 11-line chart is noisy — lets you isolate a few lines without
    /// changing the merchant-section category filter below it.
    @State private var hiddenChartCategories: Set<SpendCategory> = []
    @State private var isVisible = false

    /// Start of the selected window, truncated to a day so it is stable within
    /// a render pass and can safely take part in the cache key.
    private var windowStart: Date? {
        range.cutoff().map { Calendar.current.startOfDay(for: $0) }
    }

    /// Shared so the last snapshot is available immediately when this segment
    /// becomes active again.
    @State private var coordinator = AnalysisSnapshotCoordinator.shared

    var body: some View {
        Group {
            if let snapshot = coordinator.snapshot {
                if snapshot.isEmpty {
                    ContentUnavailableView {
                        Label("No trends yet", systemImage: "chart.line.uptrend.xyaxis")
                    } description: {
                        Text("Connect an account or import a statement to see merchant and category trends.")
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            rangePicker
                            categorySpendChart(snapshot)
                            categoryAveragesList(snapshot)
                            categoryFilterRow(snapshot)
                            merchantSection(title: "Most frequent", symbol: "repeat.circle.fill", stats: snapshot.topByFrequency, showsVisits: true)
                            merchantSection(title: "Biggest spend", symbol: "dollarsign.circle.fill", stats: snapshot.topBySpend, showsVisits: false)
                            if !snapshot.recurring.isEmpty {
                                merchantSection(title: "Recurring habits", symbol: "arrow.triangle.2.circlepath.circle.fill", stats: snapshot.recurring, showsVisits: true)
                            }
                        }
                        .padding()
                    }
                }
            } else {
                // First load only — never the empty state, which would be a
                // lie while the computation is still running.
                ProgressView("Analyzing your spending…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // The visible UI stays mounted so scroll and selection state survive a
        // segment switch. Only this data driver owns @Query, so the hidden
        // segment stops observing SwiftData and doing ledger-sized hashing.
        .background {
            if isActive && isVisible {
                AnalysisDataDriver(
                    range: $range,
                    categoryFilter: categoryFilter,
                    excludedAccountsRaw: excludedAccountsRaw,
                    availableRanges: $availableRanges,
                    coordinator: coordinator
                )
            }
        }
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            coordinator.suspend()
        }
        .onChange(of: isActive) { _, active in
            if !active { coordinator.suspend() }
        }
        .navigationDestination(item: $selectedMerchant) { stats in
            AnalysisMerchantDestination(
                stats: stats,
                excludedAccountsRaw: excludedAccountsRaw,
                windowStart: windowStart
            )
        }
        .navigationDestination(item: $selectedCategory) { category in
            AnalysisCategoryDestination(
                category: category,
                excludedAccountsRaw: excludedAccountsRaw,
                windowStart: windowStart
            )
        }
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(availableRanges) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }

    /// Lets you focus the frequency/spend/recurring sections below on a
    /// single category — e.g. tap "Dining Out" to see just restaurants.
    private func categoryFilterRow(_ snapshot: AnalysisSnapshot) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "All", symbol: "square.grid.2x2.fill", tint: .secondary, isSelected: categoryFilter == nil) {
                    categoryFilter = nil
                }
                ForEach(snapshot.availableCategories) { category in
                    filterChip(title: category.displayName, symbol: category.symbol, tint: category.tint, isSelected: categoryFilter == category) {
                        categoryFilter = (categoryFilter == category) ? nil : category
                    }
                }
            }
        }
    }

    private func filterChip(title: String, symbol: String, tint: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? tint.opacity(0.22) : Color(.secondarySystemBackground), in: Capsule())
                .foregroundStyle(isSelected ? tint : .primary)
                .overlay(Capsule().strokeBorder(isSelected ? tint : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    /// Fixed category -> color/order mapping so the legend and line colors stay
    /// stable across range switches instead of being reassigned from whichever
    /// categories happen to appear in the current window.
    private static let spendingCategoryOrder: [SpendCategory] = SpendCategory.allCases.filter { $0.isSpending }

    /// Fixed category -> point-symbol mapping, mirroring `spendingCategoryOrder`'s
    /// color scale. Without an explicit scale, Charts assigns symbols based on
    /// whichever categories are present in the current range, so switching
    /// ranges reshuffled which shape represented which category.
    private static let categorySymbols: [BasicChartSymbolShape] = [
        .circle, .square, .triangle, .diamond, .pentagon, .cross, .plus, .asterisk
    ]

    @ViewBuilder
    private func categorySpendChart(_ snapshot: AnalysisSnapshot) -> some View {
        let categoryMonthly = snapshot.categoryMonthly
        if !categoryMonthly.isEmpty {
            let visibleMonthly = categoryMonthly.filter { !hiddenChartCategories.contains($0.category) }
            VStack(alignment: .leading, spacing: 8) {
                Text("Spend by category over time")
                    .font(.headline)
                Chart(visibleMonthly) { entry in
                    LineMark(
                        x: .value("Month", entry.monthStart, unit: .month),
                        y: .value("Spent", entry.amount)
                    )
                    .foregroundStyle(by: .value("Category", entry.category.displayName))
                    .symbol(by: .value("Category", entry.category.displayName))
                }
                .chartForegroundStyleScale(
                    domain: Self.spendingCategoryOrder.map(\.displayName),
                    range: Self.spendingCategoryOrder.map(\.tint)
                )
                .chartSymbolScale(
                    domain: Self.spendingCategoryOrder.map(\.displayName),
                    range: Self.spendingCategoryOrder.indices.map { Self.categorySymbols[$0 % Self.categorySymbols.count] }
                )
                .chartYAxis {
                    AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
                }
                .chartLegend(.hidden)
                .frame(height: 220)
                CategoryLegendWrap(
                    categories: Self.spendingCategoryOrder.filter { cat in
                        categoryMonthly.contains { $0.category == cat }
                    },
                    hidden: hiddenChartCategories,
                    onToggle: { category in
                        if hiddenChartCategories.contains(category) {
                            hiddenChartCategories.remove(category)
                        } else {
                            hiddenChartCategories.insert(category)
                        }
                    },
                    onShowAll: { hiddenChartCategories.removeAll() }
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private func categoryAveragesList(_ snapshot: AnalysisSnapshot) -> some View {
        let categoryAverages = snapshot.categoryAverages
        if !categoryAverages.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Monthly category averages")
                    .font(.headline)
                ForEach(categoryAverages.prefix(6)) { average in
                    Button { selectedCategory = average.category } label: {
                        CategoryAverageRow(average: average)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                    if average.id != categoryAverages.prefix(6).last?.id {
                        Divider()
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func merchantSection(
        title: String,
        symbol: String,
        stats: [MerchantAnalytics.MerchantStats],
        showsVisits: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                    Button { selectedMerchant = stat } label: {
                        MerchantRow(stats: stat, showsVisits: showsVisits)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                    if index != stats.count - 1 { Divider() }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// A wrapping legend for the category spend chart — replaces the built-in
/// Charts legend (which doesn't wrap and clips a 5th+ category off-screen).
/// Each entry is tappable to hide/show that category's line, so a busy chart
/// with many categories can be narrowed down to just the ones you care about.
private struct CategoryLegendWrap: View {
    let categories: [SpendCategory]
    let hidden: Set<SpendCategory>
    let onToggle: (SpendCategory) -> Void
    let onShowAll: () -> Void

    var body: some View {
        FlowLayout(spacing: 10) {
            ForEach(categories) { category in
                let isHidden = hidden.contains(category)
                Button { onToggle(category) } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isHidden ? Color.secondary.opacity(0.3) : category.tint)
                            .frame(width: 8, height: 8)
                        Text(category.displayName)
                            .font(.caption2)
                            .foregroundStyle(isHidden ? .tertiary : .secondary)
                            .strikethrough(isHidden)
                    }
                }
                .buttonStyle(.plain)
            }

            // Kept in the legend rather than beside the chart's title, and
            // always laid out (only faded) rather than inserted on demand:
            // either would resize content above the chart and shove it down
            // the moment you hide a line.
            Button("Show all", action: onShowAll)
                .font(.caption2.weight(.semibold))
                .opacity(hidden.isEmpty ? 0 : 1)
                .disabled(hidden.isEmpty)
                .accessibilityHidden(hidden.isEmpty)
                .animation(.easeInOut(duration: 0.15), value: hidden.isEmpty)
        }
    }
}

/// Minimal wrapping flow layout (rows wrap instead of clipping/scrolling off-screen).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct MerchantRow: View {
    let stats: MerchantAnalytics.MerchantStats
    let showsVisits: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(stats.category.tint.opacity(0.18)).frame(width: 36, height: 36)
                Image(systemName: stats.category.symbol)
                    .font(.subheadline)
                    .foregroundStyle(stats.category.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(stats.name).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(showsVisits
                     ? "\(stats.visitCount) visit\(stats.visitCount == 1 ? "" : "s") • avg \(CurrencyFormatter.string(stats.averagePerVisit))"
                     : "avg \(CurrencyFormatter.string(stats.averagePerVisit)) • \(stats.visitCount) visit\(stats.visitCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.compact(stats.totalSpent))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                TrendBadge(trend: stats.trend)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private struct CategoryAverageRow: View {
    let average: MerchantAnalytics.CategoryAverage

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(average.category.tint.opacity(0.18)).frame(width: 32, height: 32)
                Image(systemName: average.category.symbol)
                    .font(.caption)
                    .foregroundStyle(average.category.tint)
            }
            Text(average.category.displayName)
                .font(.subheadline)
            Spacer()
            Text("\(CurrencyFormatter.string(average.averagePerMonth))/mo")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            TrendBadge(trend: average.trend)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// Owns the live SwiftData subscriptions only while Analysis is visible.
///
/// The rendered Analysis tree remains mounted in `AnalysisView`, preserving
/// scroll position and controls, while switching to Save removes this driver
/// and all of its query observation.
private struct AnalysisDataDriver: View {
    @Binding var range: AnalysisTimeRange
    let categoryFilter: SpendCategory?
    let excludedAccountsRaw: String
    @Binding var availableRanges: [AnalysisTimeRange]
    let coordinator: AnalysisSnapshotCoordinator

    @Query(sort: \TransactionRecord.date, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
    @Query private var groupingRules: [MerchantGroupingRule]

    private var windowStart: Date? {
        range.cutoff().map { Calendar.current.startOfDay(for: $0) }
    }

    private var request: AnalysisSnapshotCoordinator.Request {
        AnalysisSnapshotCoordinator.Request(
            key: AnalysisSnapshotCache.InputsKey(
                dataHash: AnalysisSnapshotCache.dataHash(transactions),
                rulesHash: AnalysisSnapshotCache.rulesHash(rules),
                groupingRulesHash: AnalysisSnapshotCache.groupingRulesHash(groupingRules),
                excludedAccountsRaw: excludedAccountsRaw,
                range: range,
                windowStart: windowStart
            ),
            categoryFilter: categoryFilter
        )
    }

    var body: some View {
        Color.clear
            .onChange(of: request, initial: true) { _, newRequest in
                let meaningfulRanges = meaningfulAnalysisRanges(for: transactions)
                availableRanges = meaningfulRanges
                guard meaningfulRanges.contains(range) else {
                    range = meaningfulRanges.last ?? .oneMonth
                    return
                }
                coordinator.refresh(
                    newRequest,
                    transactions: scopedAnalysisTransactions(
                        transactions,
                        excludedAccountsRaw: excludedAccountsRaw,
                        windowStart: windowStart
                    ).map(AnalysisTransaction.init(record:)),
                    rules: rules.map(CategoryRuleSpec.init(rule:)),
                    groupingRules: groupingRules.map(MerchantGroupingRuleSpec.init(rule:))
                )
            }
            .onDisappear { coordinator.suspend() }
            .accessibilityHidden(true)
    }
}

/// Detail destinations fetch only while they are actually pushed. Keeping
/// these queries out of `AnalysisView` lets its hidden segment fully detach
/// from SwiftData without changing the existing detail screens.
private struct AnalysisMerchantDestination: View {
    let stats: MerchantAnalytics.MerchantStats
    let excludedAccountsRaw: String
    let windowStart: Date?

    @Query(sort: \TransactionRecord.date, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]

    var body: some View {
        MerchantDetailView(
            stats: stats,
            transactions: scopedAnalysisTransactions(
                transactions,
                excludedAccountsRaw: excludedAccountsRaw,
                windowStart: windowStart
            ),
            rules: rules
        )
    }
}

private struct AnalysisCategoryDestination: View {
    let category: SpendCategory
    let excludedAccountsRaw: String
    let windowStart: Date?

    @Query(sort: \TransactionRecord.date, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]

    var body: some View {
        AnalysisCategoryDetailView(
            category: category,
            transactions: scopedAnalysisTransactions(
                transactions,
                excludedAccountsRaw: excludedAccountsRaw,
                windowStart: windowStart
            ),
            rules: rules
        )
    }
}

private func scopedAnalysisTransactions(
    _ transactions: [TransactionRecord],
    excludedAccountsRaw: String,
    windowStart: Date?
) -> [TransactionRecord] {
    let excluded = SpendingAccountFilter.excludedIds(from: excludedAccountsRaw)
    return transactions.filter { transaction in
        SpendingAccountFilter.isIncluded(transaction.accountId, excluded: excluded)
            && (windowStart == nil || transaction.date >= windowStart!)
    }
}

/// Hides range choices that would display the same history as a shorter one.
private func meaningfulAnalysisRanges(for transactions: [TransactionRecord]) -> [AnalysisTimeRange] {
    guard let earliest = transactions.lazy.map(\.date).min() else { return [.oneMonth] }
    let spanMonths = Calendar.current.dateComponents([.month], from: earliest, to: Date()).month ?? 0
    let options = AnalysisTimeRange.allCases.filter { option in
        switch option {
        case .oneMonth: return true
        case .threeMonths: return spanMonths >= 1
        case .sixMonths: return spanMonths >= 3
        case .twelveMonths: return spanMonths >= 6
        case .all: return spanMonths >= 12
        }
    }
    return options.isEmpty ? [.oneMonth] : options
}

struct TrendBadge: View {
    let trend: MerchantAnalytics.Trend

    var body: some View {
        switch trend {
        case .up(let percent):
            Label("\(Int(percent.rounded()))%", systemImage: "arrow.up.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.red)
        case .down(let percent):
            Label("\(Int(percent.rounded()))%", systemImage: "arrow.down.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.green)
        case .flat:
            Label("Flat", systemImage: "arrow.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        case .new:
            Label("New", systemImage: "sparkle")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
