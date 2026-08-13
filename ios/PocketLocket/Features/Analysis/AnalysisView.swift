import SwiftUI
import SwiftData
import Charts

/// Mines transaction history for merchant frequency, spend habits, and
/// category trends — "how many times have I eaten here", "average grocery
/// spend", "businesses I frequent" — computed entirely on-device.
struct AnalysisView: View {
    @Query(sort: \TransactionRecord.date, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
    @AppStorage(SpendingAccountFilter.key) private var excludedAccountsRaw = ""

    @State private var range: AnalysisTimeRange = .twelveMonths
    @State private var selectedMerchant: MerchantAnalytics.MerchantStats?
    @State private var selectedCategory: SpendCategory?
    @State private var categoryFilter: SpendCategory?

    /// The earliest transaction date across the *unfiltered* account/rule
    /// scope — used to decide which range options would actually change what's
    /// displayed (e.g. hide 6M/12M/All when you only have 3 months of history).
    private var earliestTransactionDate: Date? {
        transactions.map(\.date).min()
    }

    /// Only offer ranges that are either "All" or would include more history
    /// than the smallest option — otherwise every wider tab shows identical
    /// data, which is confusing with a short transaction history.
    private var availableRanges: [AnalysisTimeRange] {
        guard let earliest = earliestTransactionDate else { return [.oneMonth] }
        let now = Date()
        let spanMonths = Calendar.current.dateComponents([.month], from: earliest, to: now).month ?? 0
        var options = AnalysisTimeRange.allCases.filter { option in
            switch option {
            case .oneMonth: return true
            case .threeMonths: return spanMonths >= 1
            case .sixMonths: return spanMonths >= 3
            case .twelveMonths: return spanMonths >= 6
            case .all: return spanMonths >= 12
            }
        }
        // Always keep at least one option so the picker never renders empty.
        if options.isEmpty { options = [.oneMonth] }
        return options
    }

    private var scoped: [TransactionRecord] {
        let excluded = SpendingAccountFilter.excludedIds(from: excludedAccountsRaw)
        let cutoff = range.cutoff()
        return transactions.filter { txn in
            SpendingAccountFilter.isIncluded(txn.accountId, excluded: excluded)
                && (cutoff == nil || txn.date >= cutoff!)
        }
    }

    private var inputs: [MerchantAnalytics.Input] {
        scoped.map {
            MerchantAnalytics.Input(
                title: $0.title,
                amount: $0.amount,
                category: $0.resolvedCategory(using: rules),
                date: $0.date
            )
        }
    }

    /// Categories present in the un-filtered window, used to build the filter
    /// chip row (only shows categories that actually have data).
    private var availableCategories: [SpendCategory] {
        let present = Set(inputs.filter { $0.category.isSpending }.map(\.category))
        return SpendCategory.allCases.filter { present.contains($0) }
    }

    private var filteredInputs: [MerchantAnalytics.Input] {
        guard let categoryFilter else { return inputs }
        return inputs.filter { $0.category == categoryFilter }
    }

    private var merchantStats: [MerchantAnalytics.MerchantStats] {
        MerchantAnalytics.merchantStats(inputs)
    }

    private var filteredMerchantStats: [MerchantAnalytics.MerchantStats] {
        MerchantAnalytics.merchantStats(filteredInputs)
    }

    private var topByFrequency: [MerchantAnalytics.MerchantStats] {
        MerchantAnalytics.topByFrequency(filteredMerchantStats, limit: 8)
    }

    private var topBySpend: [MerchantAnalytics.MerchantStats] {
        MerchantAnalytics.topBySpend(filteredMerchantStats, limit: 8)
    }

    private var categoryAverages: [MerchantAnalytics.CategoryAverage] {
        MerchantAnalytics.categoryAverages(inputs)
    }

    private var categoryMonthly: [MerchantAnalytics.CategoryMonth] {
        MerchantAnalytics.categoryMonthlyTotals(inputs)
    }

    var body: some View {
        NavigationStack {
            Group {
                if merchantStats.isEmpty {
                    ContentUnavailableView {
                        Label("No trends yet", systemImage: "chart.line.uptrend.xyaxis")
                    } description: {
                        Text("Connect an account or import a statement to see merchant and category trends.")
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            rangePicker
                            categorySpendChart
                            categoryAveragesList
                            categoryFilterRow
                            merchantSection(title: "Most frequent", symbol: "repeat.circle.fill", stats: topByFrequency, showsVisits: true)
                            merchantSection(title: "Biggest spend", symbol: "dollarsign.circle.fill", stats: topBySpend, showsVisits: false)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedMerchant) { stats in
                MerchantDetailView(stats: stats, transactions: scoped, rules: rules)
            }
            .navigationDestination(item: $selectedCategory) { category in
                AnalysisCategoryDetailView(category: category, transactions: scoped, rules: rules)
            }
        }
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(availableRanges) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .onAppear { clampRangeToAvailable() }
        .onChange(of: availableRanges) { _, _ in clampRangeToAvailable() }
    }

    /// If the selected range isn't one of the currently meaningful options
    /// (e.g. history just got shorter, or the default 12M isn't reachable yet
    /// with only a few months of data), fall back to the widest one that is.
    private func clampRangeToAvailable() {
        guard !availableRanges.contains(range), let widest = availableRanges.last else { return }
        range = widest
    }

    /// Lets you focus the frequency/spend sections below on a single
    /// category — e.g. tap "Dining Out" to see just restaurants.
    private var categoryFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "All", symbol: "square.grid.2x2.fill", tint: .secondary, isSelected: categoryFilter == nil) {
                    categoryFilter = nil
                }
                ForEach(availableCategories) { category in
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
    private var categorySpendChart: some View {
        if !categoryMonthly.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Spend by category over time")
                    .font(.headline)
                Chart(categoryMonthly) { entry in
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
                CategoryLegendWrap(categories: Self.spendingCategoryOrder.filter { cat in
                    categoryMonthly.contains { $0.category == cat }
                })
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private var categoryAveragesList: some View {
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
private struct CategoryLegendWrap: View {
    let categories: [SpendCategory]

    var body: some View {
        FlowLayout(spacing: 10) {
            ForEach(categories) { category in
                HStack(spacing: 4) {
                    Circle().fill(category.tint).frame(width: 8, height: 8)
                    Text(category.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
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
        }
    }
}
