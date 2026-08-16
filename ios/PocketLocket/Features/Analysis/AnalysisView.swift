import SwiftUI
import SwiftData
import Charts

private enum CategoryComparisonMode: String, CaseIterable, Identifiable {
    case monthlyAverage
    case previousMonth

    var id: Self { self }
}

private struct CategoryComparisonContext {
    let monthDate: Date

    var monthLabel: String {
        monthDate.formatted(.dateTime.month(.wide).year())
    }

    var isCurrentMonth: Bool {
        Calendar.current.isDate(
            monthDate,
            equalTo: Date(),
            toGranularity: .month
        )
    }

    var previousMonthDate: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: monthDate)
            ?? monthDate
    }

    var previousMonthLabel: String {
        previousMonthDate.formatted(.dateTime.month(.wide).year())
    }

    var previousMonthShortLabel: String {
        previousMonthDate.formatted(.dateTime.month(.abbreviated))
    }
}

private enum SpendingChartMode: String, CaseIterable, Identifiable {
    case cumulative
    case rolling30Day

    var id: Self { self }
}

/// Mines transaction history for merchant frequency, spend habits, and
/// category trends — "how many times have I eaten here", "average grocery
/// spend", "businesses I frequent" — computed entirely on-device.
struct AnalysisView: View {
    var showSavingsPlan: () -> Void

    @AppStorage("monthlyBudget") private var monthlyBudget: Double = 3000
    @AppStorage(SpendingAccountFilter.key) private var excludedAccountsRaw = ""

    @State private var selectedWindow: DateInterval?
    @State private var windowDomain = AnalysisDateWindow.domain(for: [])
    @State private var previewWindow: DateInterval?
    @State private var selectedMerchant: MerchantAnalytics.MerchantStats?
    @State private var selectedCategory: SpendCategory?
    @State private var categoryFilter: SpendCategory?
    @State private var categoryComparisonMode: CategoryComparisonMode = .monthlyAverage
    @State private var spendingChartMode: SpendingChartMode = .cumulative
    @State private var selectedChartDate: Date?
    @State private var questionEntries: [TransactionQuestionContext.Entry]?
    /// Categories tapped "off" in the chart legend, per Vamsi's feedback that
    /// the 11-line chart is noisy — lets you isolate a few lines without
    /// changing the merchant-section category filter below it.
    @State private var hiddenChartCategories: Set<SpendCategory> = []
    @State private var isVisible = false

    private var analysisWindow: DateInterval {
        AnalysisDateWindow.snappedToMonths(
            AnalysisDateWindow.clamped(
                selectedWindow ?? AnalysisDateWindow.defaultSelection(in: windowDomain),
                to: windowDomain
            ),
            in: windowDomain
        )
    }

    private var windowFractions: ClosedRange<Double> {
        AnalysisDateWindow.fractions(for: analysisWindow, in: windowDomain)
    }

    /// Shared so the last completed work is immediately available on return.
    @State private var coordinator = AnalysisSnapshotCoordinator.shared
    @State private var savingsCoordinator = SavingsSuggestionsCoordinator.shared

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
                            if AIInsightService.isAvailable {
                                AskPocketLocketCard(
                                    entries: questionEntries ?? [],
                                    monthlyBudget: monthlyBudget
                                )
                            }
                            SavingsQuickWins(
                                suggestions: savingsCoordinator.suggestions ?? [],
                                action: showSavingsPlan
                            )
                            categoryAveragesList(snapshot)
                            categorySpendChart(snapshot)
                            analysisPeriodControl
                            categoryFilterRow(snapshot)
                            merchantSection(title: "Most frequent", symbol: "repeat.circle.fill", stats: snapshot.topByFrequency, showsVisits: true)
                            merchantSection(title: "Biggest spend", symbol: "dollarsign.circle.fill", stats: snapshot.topBySpend, showsVisits: false)
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
        // The visible tree stays query-free; this one driver owns every live
        // SwiftData subscription used by Insights and Savings Plan.
        .background {
            if isVisible {
                AnalysisDataDriver(
                    selectedWindow: $selectedWindow,
                    windowDomain: $windowDomain,
                    categoryFilter: categoryFilter,
                    excludedAccountsRaw: excludedAccountsRaw,
                    monthlyBudget: monthlyBudget,
                    questionEntries: $questionEntries,
                    analysisCoordinator: coordinator,
                    savingsCoordinator: savingsCoordinator
                )
            }
        }
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            coordinator.suspend()
        }
        .navigationDestination(item: $selectedMerchant) { stats in
            AnalysisMerchantDestination(
                stats: stats,
                excludedAccountsRaw: excludedAccountsRaw,
                window: analysisWindow
            )
        }
        .navigationDestination(item: $selectedCategory) { category in
            AnalysisCategoryDestination(
                category: category,
                excludedAccountsRaw: excludedAccountsRaw,
                window: analysisWindow
            )
        }
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

    private var analysisPeriodControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Analysis period", systemImage: "calendar")
                .font(.headline)

            AnalysisWindowBar(
                selection: windowFractions,
                domain: windowDomain,
                onChange: { fractions in
                    selectedChartDate = nil
                    previewWindow = AnalysisDateWindow.interval(
                        for: fractions,
                        in: windowDomain
                    )
                }
            ) { fractions in
                selectedChartDate = nil
                selectedWindow = AnalysisDateWindow.interval(
                    for: fractions,
                    in: windowDomain
                )
                previewWindow = nil
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    @ViewBuilder
    private func categorySpendChart(_ snapshot: AnalysisSnapshot) -> some View {
        let chartSource = spendingChartMode == .cumulative
            ? snapshot.categoryCumulative
            : snapshot.categoryMonthly
        if !chartSource.isEmpty {
            let windowMonthly = chartSource.filter {
                $0.monthStart >= chartWindow.start && $0.monthStart < chartWindow.end
            }
            let chartCategories = Self.spendingCategoryOrder.filter { category in
                windowMonthly.contains { $0.category == category }
            }
            let visibleMonthly = windowMonthly.filter { !hiddenChartCategories.contains($0.category) }
            let selectedSampleDate = nearestChartDate(to: selectedChartDate, in: visibleMonthly)
            let displayDate = selectedSampleDate ?? visibleMonthly.last?.monthStart
            let displayEntries = displayDate.map { date in
                visibleMonthly.filter { $0.monthStart == date }
            } ?? []
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(spendingChartMode == .cumulative ? "Cumulative Spending" : "30-Day Spending Trend")
                        .font(.headline)
                    Spacer()
                    Menu {
                        Button {
                            hiddenChartCategories.removeAll()
                        } label: {
                            Label("Show All", systemImage: "eye")
                        }
                        .disabled(hiddenChartCategories.isEmpty)

                        Button {
                            hiddenChartCategories.formUnion(chartCategories)
                        } label: {
                            Label("Hide All", systemImage: "eye.slash")
                        }
                        .disabled(chartCategories.allSatisfy(hiddenChartCategories.contains))

                        Divider()

                        ForEach(chartCategories) { category in
                            let isVisible = !hiddenChartCategories.contains(category)
                            Button { toggleChartCategory(category) } label: {
                                Label(
                                    category.displayName,
                                    systemImage: isVisible ? "checkmark.circle.fill" : "circle"
                                )
                            }
                        }
                    } label: {
                        Label("Categories", systemImage: "line.3.horizontal.decrease.circle")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Picker("Chart mode", selection: $spendingChartMode) {
                    Text("Cumulative").tag(SpendingChartMode.cumulative)
                    Text("30-Day Trend").tag(SpendingChartMode.rolling30Day)
                }
                .pickerStyle(.segmented)
                .onChange(of: spendingChartMode) { _, _ in selectedChartDate = nil }
                if let displayDate {
                    HStack(alignment: .firstTextBaseline) {
                        Text(displayDate.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(CurrencyFormatter.string(displayEntries.reduce(0) { $0 + $1.amount }))
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                            Text(spendingChartMode == .cumulative
                                ? "visible total in range"
                                : "smoothed 30-day total")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 34)
                }
                Chart {
                    ForEach(visibleMonthly) { entry in
                        LineMark(
                            x: .value("Date", entry.monthStart),
                            y: .value("Spent", entry.amount)
                        )
                        .foregroundStyle(by: .value("Category", entry.category.displayName))
                        .interpolationMethod(spendingChartMode == .cumulative ? .stepEnd : .monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    if let selectedSampleDate {
                        RuleMark(x: .value("Selected date", selectedSampleDate))
                            .foregroundStyle(.secondary.opacity(0.75))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        ForEach(displayEntries) { entry in
                            PointMark(
                                x: .value("Date", entry.monthStart),
                                y: .value("Spent", entry.amount)
                            )
                            .foregroundStyle(by: .value("Category", entry.category.displayName))
                            .symbolSize(42)
                        }
                    }
                }
                .chartForegroundStyleScale(
                    domain: Self.spendingCategoryOrder.map(\.displayName),
                    range: Self.spendingCategoryOrder.map(\.tint)
                )
                .chartYAxis {
                    AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
                }
                .chartXScale(domain: chartWindow.start...chartDisplayEnd)
                .chartLegend(.hidden)
                .chartXSelection(value: $selectedChartDate)
                .frame(height: 220)
                .sensoryFeedback(.selection, trigger: selectedSampleDate)
                CategoryLegendWrap(
                    categories: chartCategories,
                    hidden: hiddenChartCategories,
                    onToggle: toggleChartCategory,
                    onShowAll: { hiddenChartCategories.removeAll() }
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func toggleChartCategory(_ category: SpendCategory) {
        if hiddenChartCategories.contains(category) {
            hiddenChartCategories.remove(category)
        } else {
            hiddenChartCategories.insert(category)
        }
    }

    private func nearestChartDate(
        to selection: Date?,
        in entries: [MerchantAnalytics.CategoryMonth]
    ) -> Date? {
        guard let selection, let firstCategory = entries.first?.category else { return nil }
        return entries.lazy.filter { $0.category == firstCategory }.min {
            abs($0.monthStart.timeIntervalSince(selection))
                < abs($1.monthStart.timeIntervalSince(selection))
        }?.monthStart
    }

    @ViewBuilder
    private func categoryAveragesList(_ snapshot: AnalysisSnapshot) -> some View {
        let categoryAverages = snapshot.categoryAverages
        let comparison = CategoryComparisonContext(
            monthDate: snapshot.comparisonMonthStart
                ?? Calendar.current.dateInterval(of: .month, for: Date())?.start
                ?? Date()
        )
        if !categoryAverages.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Compare \(comparison.monthLabel) against")
                        .font(.headline)
                    Picker(
                        "Compare \(comparison.monthLabel) spending against",
                        selection: $categoryComparisonMode
                    ) {
                        Text("Prior average").tag(CategoryComparisonMode.monthlyAverage)
                        Text("Previous month").tag(CategoryComparisonMode.previousMonth)
                    }
                    .pickerStyle(.segmented)
                    Text(comparisonBaselineDescription(
                        priorMonthCount: categoryAverages.first?.priorMonthCount ?? 0,
                        previousMonthIsComplete:
                            categoryAverages.first?.previousMonthIsComplete ?? false,
                        comparison: comparison
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(categoryAverages.prefix(6)) { average in
                    Button { selectedCategory = average.category } label: {
                        CategoryAverageRow(
                            average: average,
                            comparisonMode: categoryComparisonMode,
                            previousMonthLabel: comparison.previousMonthShortLabel
                        )
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

    private func comparisonBaselineDescription(
        priorMonthCount: Int,
        previousMonthIsComplete: Bool,
        comparison: CategoryComparisonContext
    ) -> String {
        let currentMonthContext = comparison.isCurrentMonth
            ? "\(comparison.monthLabel) spending is month to date. "
            : ""
        switch categoryComparisonMode {
        case .monthlyAverage:
            guard priorMonthCount > 0 else {
                return currentMonthContext
                    + "No complete prior months are available in your history."
            }
            let months = priorMonthCount == 1
                ? "the 1 complete prior month"
                : "all \(priorMonthCount) complete prior months"
            return currentMonthContext
                + "Comparison across \(months) in your available history."
        case .previousMonth:
            guard previousMonthIsComplete else {
                return currentMonthContext + "\(comparison.previousMonthLabel) is incomplete, "
                    + "so no comparison is available."
            }
            return currentMonthContext
                + "Direct comparison with \(comparison.previousMonthLabel)."
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

    private var chartWindow: DateInterval {
        AnalysisDateWindow.clamped(previewWindow ?? analysisWindow, to: windowDomain)
    }

    private var chartDisplayEnd: Date {
        let calendar = Calendar.current
        let lastWindowDay = calendar.date(byAdding: .day, value: -1, to: chartWindow.end)
            ?? chartWindow.end
        return min(lastWindowDay, calendar.startOfDay(for: Date()))
    }
}

private struct AnalysisWindowBar: View {
    let selection: ClosedRange<Double>
    let domain: DateInterval
    let onChange: (ClosedRange<Double>) -> Void
    let onCommit: (ClosedRange<Double>) -> Void

    @State private var draftSelection: ClosedRange<Double>?
    @State private var dragStartSelection: ClosedRange<Double>?
    @State private var dragTarget: DragTarget?

    private enum DragTarget { case lowerHandle, upperHandle, window }

    private var displayedSelection: ClosedRange<Double> {
        snapped(draftSelection ?? selection)
    }

    private var boundaryFractions: [Double] {
        AnalysisDateWindow.monthBoundaries(in: domain).map {
            AnalysisDateWindow.fraction(for: $0, in: domain)
        }
    }

    private var tickFractions: [Double] {
        let boundaries = boundaryFractions
        let step = max(Int(ceil(Double(max(boundaries.count - 1, 1)) / 24)), 1)
        var ticks: [Double] = []
        for (index, fraction) in boundaries.enumerated() {
            if index.isMultiple(of: step) || index == boundaries.count - 1 {
                ticks.append(fraction)
            }
        }
        return ticks
    }

    private var selectedMonthCount: Int {
        max(
            nearestBoundaryIndex(to: displayedSelection.upperBound)
                - nearestBoundaryIndex(to: displayedSelection.lowerBound),
            1
        )
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label(for: displayedSelection.lowerBound, isUpperBound: false))
                Spacer()
                Label("\(selectedMonthCount) mo", systemImage: "calendar")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(label(for: displayedSelection.upperBound, isUpperBound: true))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()

            GeometryReader { geometry in
                let inset: CGFloat = 14
                let width = max(geometry.size.width - inset * 2, 1)
                let lowerX = inset + width * displayedSelection.lowerBound
                let upperX = inset + width * displayedSelection.upperBound

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: width, height: 4)
                        .offset(x: inset)
                    ForEach(tickFractions, id: \.self) { fraction in
                        Capsule()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 1, height: 8)
                            .position(x: inset + width * fraction, y: 16)
                    }
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(upperX - lowerX, 4), height: 8)
                        .offset(x: lowerX)
                    handle.position(x: lowerX, y: 16)
                    handle.position(x: upperX, y: 16)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(width: width, inset: inset))
            }
            .frame(height: 32)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Analysis date window")
        .accessibilityValue(
            "\(label(for: displayedSelection.lowerBound, isUpperBound: false)) to "
                + label(for: displayedSelection.upperBound, isUpperBound: true)
        )
        .accessibilityAdjustableAction { direction in
            commitShiftedWindow(byMonths: direction == .increment ? 1 : -1)
        }
    }

    private var handle: some View {
        Circle()
            .fill(Color(.systemBackground))
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 3))
            .frame(width: 26, height: 26)
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }

    private func dragGesture(width: CGFloat, inset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let start = dragStartSelection ?? displayedSelection
                let target: DragTarget
                if let dragTarget {
                    target = dragTarget
                } else {
                    target = targetForDrag(
                        at: value.startLocation.x,
                        selection: start,
                        width: width,
                        inset: inset
                    )
                    self.dragTarget = target
                    dragStartSelection = start
                }

                let fraction = min(max((value.location.x - inset) / width, 0), 1)
                let lowerIndex = nearestBoundaryIndex(to: start.lowerBound)
                let upperIndex = nearestBoundaryIndex(to: start.upperBound)
                switch target {
                case .lowerHandle:
                    let index = min(nearestBoundaryIndex(to: fraction), upperIndex - 1)
                    draftSelection = range(lowerIndex: max(index, 0), upperIndex: upperIndex)
                case .upperHandle:
                    let index = max(nearestBoundaryIndex(to: fraction), lowerIndex + 1)
                    draftSelection = range(
                        lowerIndex: lowerIndex,
                        upperIndex: min(index, boundaryFractions.count - 1)
                    )
                case .window:
                    let span = upperIndex - lowerIndex
                    let delta = value.translation.width / width
                    let proposedLower = nearestBoundaryIndex(to: start.lowerBound + delta)
                    let newLower = min(max(proposedLower, 0), boundaryFractions.count - 1 - span)
                    draftSelection = range(lowerIndex: newLower, upperIndex: newLower + span)
                }
                if let draftSelection { onChange(draftSelection) }
            }
            .onEnded { _ in
                onCommit(snapped(draftSelection ?? selection))
                draftSelection = nil
                dragStartSelection = nil
                dragTarget = nil
            }
    }

    private func targetForDrag(
        at location: CGFloat,
        selection: ClosedRange<Double>,
        width: CGFloat,
        inset: CGFloat
    ) -> DragTarget {
        let lowerX = inset + width * selection.lowerBound
        let upperX = inset + width * selection.upperBound
        let lowerDistance = abs(location - lowerX)
        let upperDistance = abs(location - upperX)
        if min(lowerDistance, upperDistance) <= 24 {
            return lowerDistance <= upperDistance ? .lowerHandle : .upperHandle
        }
        if location > lowerX, location < upperX { return .window }
        return lowerDistance <= upperDistance ? .lowerHandle : .upperHandle
    }

    private func commitShiftedWindow(byMonths delta: Int) {
        let lowerIndex = nearestBoundaryIndex(to: selection.lowerBound)
        let upperIndex = nearestBoundaryIndex(to: selection.upperBound)
        let span = upperIndex - lowerIndex
        let shiftedLower = min(max(lowerIndex + delta, 0), boundaryFractions.count - 1 - span)
        onCommit(range(lowerIndex: shiftedLower, upperIndex: shiftedLower + span))
    }

    private func nearestBoundaryIndex(to fraction: Double) -> Int {
        boundaryFractions.indices.min {
            abs(boundaryFractions[$0] - fraction) < abs(boundaryFractions[$1] - fraction)
        } ?? 0
    }

    private func range(lowerIndex: Int, upperIndex: Int) -> ClosedRange<Double> {
        boundaryFractions[lowerIndex]...boundaryFractions[upperIndex]
    }

    private func snapped(_ fractions: ClosedRange<Double>) -> ClosedRange<Double> {
        let interval = AnalysisDateWindow.interval(for: fractions, in: domain)
        let snapped = AnalysisDateWindow.snappedToMonths(interval, in: domain)
        return AnalysisDateWindow.fractions(for: snapped, in: domain)
    }

    private func label(for fraction: Double, isUpperBound: Bool) -> String {
        var date = AnalysisDateWindow.date(for: fraction, in: domain)
        if isUpperBound, date > domain.start { date = date.addingTimeInterval(-1) }
        return date.formatted(.dateTime.month(.abbreviated).year())
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
    let comparisonMode: CategoryComparisonMode
    let previousMonthLabel: String

    private var baselineAmount: Double {
        switch comparisonMode {
        case .monthlyAverage: average.priorMonthsAverage
        case .previousMonth: average.previousMonthSpend
        }
    }

    private var hasBaseline: Bool {
        switch comparisonMode {
        case .monthlyAverage: average.priorMonthCount > 0
        case .previousMonth: average.previousMonthIsComplete
        }
    }

    private var trend: MerchantAnalytics.Trend {
        switch comparisonMode {
        case .monthlyAverage: average.priorAverageTrend
        case .previousMonth: average.previousMonthTrend
        }
    }

    private var baselineLabel: String {
        switch comparisonMode {
        case .monthlyAverage:
            return "\(CurrencyFormatter.compact(baselineAmount)) avg"
        case .previousMonth:
            return "\(CurrencyFormatter.compact(baselineAmount)) \(previousMonthLabel)"
        }
    }

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
                .lineLimit(1)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.compact(average.currentMonthSpend))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if hasBaseline {
                    Text(baselineLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if hasBaseline {
                TrendBadge(trend: trend)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// Owns every live SwiftData subscription used by Insights and Savings Plan.
private struct AnalysisDataDriver: View {
    struct Request: Equatable {
        let analysis: AnalysisSnapshotCoordinator.Request
        let savings: SavingsSuggestionsCoordinator.Request
        let questionDataHash: Int
        let domain: DateInterval
    }

    @Binding var selectedWindow: DateInterval?
    @Binding var windowDomain: DateInterval
    let categoryFilter: SpendCategory?
    let excludedAccountsRaw: String
    let monthlyBudget: Double
    @Binding var questionEntries: [TransactionQuestionContext.Entry]?
    let analysisCoordinator: AnalysisSnapshotCoordinator
    let savingsCoordinator: SavingsSuggestionsCoordinator

    @Query(sort: \TransactionRecord.date, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
    @Query private var groupingRules: [MerchantGroupingRule]
    @Query private var reimbursementAllocations: [ReimbursementAllocation]

    private var excludedAccountIDs: Set<String> {
        SpendingAccountFilter.excludedIds(from: excludedAccountsRaw)
    }

    private var includedTransactions: [TransactionRecord] {
        transactions.filter {
            SpendingAccountFilter.isIncluded($0.accountId, excluded: excludedAccountIDs)
        }
    }

    private func analysisTransaction(
        _ transaction: TransactionRecord,
        reimbursementIndex: ReimbursementAllocationIndex
    ) -> AnalysisTransaction {
        AnalysisTransaction(
            record: transaction,
            effectiveAmount: reimbursementIndex.effectiveExpenseAmount(
                transactionID: transaction.id,
                originalAmount: transaction.amount
            )
        )
    }

    private var domain: DateInterval {
        let included = includedTransactions
        return AnalysisDateWindow.domain(
            for: [included.last?.date, included.first?.date].compactMap { $0 }
        )
    }

    private var analysisWindow: DateInterval {
        AnalysisDateWindow.snappedToMonths(
            AnalysisDateWindow.clamped(
                selectedWindow ?? AnalysisDateWindow.defaultSelection(in: domain),
                to: domain
            ),
            in: domain
        )
    }

    private var currentMonth: DateInterval {
        Calendar.current.dateInterval(of: .month, for: Date())
            ?? DateInterval(start: .distantPast, duration: 0)
    }

    private var previousMonth: DateInterval {
        let calendar = Calendar.current
        guard let previous = calendar.date(byAdding: .month, value: -1, to: Date()),
              let interval = calendar.dateInterval(of: .month, for: previous)
        else { return DateInterval(start: .distantPast, duration: 0) }
        return interval
    }

    private var suggestionTransactions: [TransactionRecord] {
        includedTransactions.filter {
            $0.date >= previousMonth.start && $0.date < currentMonth.end
        }
    }

    private var questionTransactions: [TransactionRecord] {
        let cutoff = Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? .distantPast
        return Array(includedTransactions.lazy.filter { $0.date >= cutoff }.prefix(120))
    }

    private var request: Request {
        let included = includedTransactions
        let suggestions = suggestionTransactions
        let questions = questionTransactions
        return Request(
            analysis: AnalysisSnapshotCoordinator.Request(
                key: AnalysisSnapshotCache.InputsKey(
                    dataHash: AnalysisSnapshotCache.dataHash(included),
                    rulesHash: AnalysisSnapshotCache.rulesHash(rules),
                    groupingRulesHash: AnalysisSnapshotCache.groupingRulesHash(groupingRules),
                    reimbursementsHash: RecordHash.reimbursements(reimbursementAllocations),
                    excludedAccountsRaw: excludedAccountsRaw
                ),
                window: analysisWindow,
                chartEnd: Calendar.current.startOfDay(for: Date()),
                categoryFilter: categoryFilter
            ),
            savings: SavingsSuggestionsCoordinator.Request(
                key: SavingsSuggestionsCache.InputsKey(
                    dataHash: RecordHash.transactions(suggestions),
                    rulesHash: RecordHash.rules(rules),
                    reimbursementsHash: RecordHash.reimbursements(reimbursementAllocations),
                    excludedAccountsRaw: excludedAccountsRaw,
                    monthlyBudget: monthlyBudget,
                    monthStart: currentMonth.start
                )
            ),
            questionDataHash: RecordHash.transactions(questions),
            domain: domain
        )
    }

    var body: some View {
        Color.clear
            .onChange(of: request, initial: true) { _, newRequest in
                if windowDomain != newRequest.domain {
                    windowDomain = newRequest.domain
                }
                if let selectedWindow {
                    let clamped = AnalysisDateWindow.clamped(selectedWindow, to: newRequest.domain)
                    if clamped != selectedWindow { self.selectedWindow = clamped }
                }
                refresh(newRequest)
            }
            .onDisappear {
                analysisCoordinator.suspend()
            }
            .accessibilityHidden(true)
    }

    private func refresh(_ request: Request) {
        let ruleSpecs = rules.map(CategoryRuleSpec.init(rule:))
        let included = includedTransactions
        let reimbursementIndex = ReimbursementAllocationIndex(reimbursementAllocations)
        analysisCoordinator.refresh(
            request.analysis,
            transactions: included.map {
                analysisTransaction($0, reimbursementIndex: reimbursementIndex)
            },
            rules: ruleSpecs,
            groupingRules: groupingRules.map(MerchantGroupingRuleSpec.init(rule:))
        )

        questionEntries = questionTransactions.compactMap { transaction in
            let amount = reimbursementIndex.effectiveLedgerAmount(
                transactionID: transaction.id,
                originalAmount: transaction.amount
            )
            guard abs(amount) > 0.005 else { return nil }
            return TransactionQuestionContext.Entry(
                date: transaction.date,
                title: transaction.title,
                amount: amount,
                currency: transaction.isoCurrencyCode,
                category: transaction.resolvedCategory(using: rules).displayName
            )
        }

        savingsCoordinator.refresh(
            request.savings,
            transactions: suggestionTransactions.map {
                analysisTransaction($0, reimbursementIndex: reimbursementIndex)
            },
            rules: ruleSpecs,
            currentMonth: currentMonth,
            previousMonth: previousMonth,
            monthlyBudget: monthlyBudget
        )
    }
}

/// Detail destinations fetch only while they are actually pushed. Keeping
/// these queries out of `AnalysisView` lets its hidden segment fully detach
/// from SwiftData without changing the existing detail screens.
private struct AnalysisMerchantDestination: View {
    let stats: MerchantAnalytics.MerchantStats
    let excludedAccountsRaw: String
    let window: DateInterval

    @Query(sort: \TransactionRecord.date, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
    @Query private var reimbursementAllocations: [ReimbursementAllocation]

    var body: some View {
        MerchantDetailView(
            stats: stats,
            transactions: scopedAnalysisTransactions(
                transactions,
                excludedAccountsRaw: excludedAccountsRaw,
                window: window
            ),
            rules: rules,
            reimbursementAllocations: reimbursementAllocations
        )
    }
}

private struct AnalysisCategoryDestination: View {
    let category: SpendCategory
    let excludedAccountsRaw: String
    let window: DateInterval

    @Query(sort: \TransactionRecord.date, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
    @Query private var reimbursementAllocations: [ReimbursementAllocation]

    var body: some View {
        AnalysisCategoryDetailView(
            category: category,
            transactions: scopedAnalysisTransactions(
                transactions,
                excludedAccountsRaw: excludedAccountsRaw,
                window: window
            ),
            rules: rules,
            reimbursementAllocations: reimbursementAllocations
        )
    }
}

private func scopedAnalysisTransactions(
    _ transactions: [TransactionRecord],
    excludedAccountsRaw: String,
    window: DateInterval
) -> [TransactionRecord] {
    let excluded = SpendingAccountFilter.excludedIds(from: excludedAccountsRaw)
    return transactions.filter { transaction in
        SpendingAccountFilter.isIncluded(transaction.accountId, excluded: excluded)
            && transaction.date >= window.start
            && transaction.date < window.end
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
        case .new:
            Label("New", systemImage: "sparkle")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
