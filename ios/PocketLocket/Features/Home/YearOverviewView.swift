import SwiftUI
import SwiftData
import Charts

/// A yearly spending overview: total for the year, a per-month bar chart, and
/// the category breakdown. History accumulates locally as you sync and import,
/// so this fills in over time even though a live sync only fetches recent data.
struct YearOverviewView: View {
    var onSelectMonth: ((Int, Int) -> Void)? = nil

    @Query(sort: \TransactionRecord.date, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
    @AppStorage(SpendingAccountFilter.key) private var excludedAccountsRaw = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var yearOffset = 0
    @State private var summaryCache = DerivedCache<YearKey, YearSummary>()

    private var year: Int {
        Calendar.current.component(.year, from: Date()) + yearOffset
    }

    private var earliestYear: Int {
        guard let earliest = transactions.map(\.date).min() else {
            return Calendar.current.component(.year, from: Date())
        }
        return Calendar.current.component(.year, from: earliest)
    }

    /// Everything the year view shows, derived in a single pass.
    private struct YearSummary {
        let spends: [CategorySpend]
        let total: Double
        let monthlyTotals: [MonthBar]
    }

    private struct YearKey: Equatable {
        var dataHash: Int
        var rulesHash: Int
        var year: Int
        var excludedAccountsRaw: String
    }

    /// `total` alone was read three times, and each read rebuilt `spends`,
    /// which rebuilt `yearTransactions` — so a render filtered a year out of
    /// the whole ledger about six times over. Categories were resolved twice
    /// per transaction on top of that, once for the breakdown and again for
    /// the monthly bars.
    private var summary: YearSummary {
        // Narrow to the year before hashing, so the cache key costs a scan of
        // scalars rather than a hash of the whole ledger.
        let excluded = SpendingAccountFilter.excludedIds(from: excludedAccountsRaw)
        let calendar = Calendar.current
        let yearTransactions = transactions.filter {
            calendar.component(.year, from: $0.date) == year
                && SpendingAccountFilter.isIncluded($0.accountId, excluded: excluded)
        }
        let key = YearKey(
            dataHash: RecordHash.transactions(yearTransactions),
            rulesHash: RecordHash.rules(rules),
            year: year,
            excludedAccountsRaw: excludedAccountsRaw
        )
        return summaryCache.value(for: key) {
            var items: [SpendItem] = []
            var buckets = Array(repeating: 0.0, count: 12)

            for txn in yearTransactions {
                let category = txn.resolvedCategory(using: rules)
                items.append(SpendItem(category: category, amount: txn.amount))
                guard category.isSpending, txn.amount > 0 else { continue }
                let index = calendar.component(.month, from: txn.date) - 1
                if index >= 0, index < 12 { buckets[index] += txn.amount }
            }

            let spends = SpendAggregator.totals(items)
            return YearSummary(
                spends: spends,
                total: SpendAggregator.totalSpend(spends),
                monthlyTotals: buckets.enumerated().map { MonthBar(month: $0.offset, amount: $0.element) }
            )
        }
    }

    private var yearInterval: DateInterval {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? start
        return DateInterval(start: start, end: end)
    }

    struct MonthBar: Identifiable {
        let month: Int
        let amount: Double
        var id: Int { month }
        var label: String { Calendar.current.shortMonthSymbols[month] }
    }

    var body: some View {
        content(summary)
    }

    private func content(_ summary: YearSummary) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                yearSwitcher

                VStack(spacing: 4) {
                    Text(CurrencyFormatter.string(summary.total))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("spent in \(String(year))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if summary.total == 0 {
                    ContentUnavailableView {
                        Label("No spending in \(String(year))", systemImage: "calendar")
                    } description: {
                        Text("History builds up here as you sync and import statements.")
                    }
                    .padding(.top, 12)
                } else {
                    chart(summary.monthlyTotals)
                    CategoryBreakdownList(spends: summary.spends, total: summary.total, interval: yearInterval, periodLabel: String(year))
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    private func chart(_ monthlyTotals: [MonthBar]) -> some View {
        Chart(monthlyTotals) { bar in
            BarMark(
                x: .value("Month", bar.label),
                y: .value("Spent", bar.amount)
            )
            .foregroundStyle(.tint)
            .cornerRadius(4)
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        guard let plotFrame = proxy.plotFrame else { return }
                        let relativeX = location.x - geo[plotFrame].origin.x
                        if let label: String = proxy.value(atX: relativeX),
                           let index = Calendar.current.shortMonthSymbols.firstIndex(of: label) {
                            onSelectMonth?(year, index)
                        }
                    }
            }
        }
        .chartYAxis {
            AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
        }
        .frame(height: 220)
        .padding(.horizontal)
    }

    private var yearSwitcher: some View {
        HStack {
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { yearOffset -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .liquidGlassCircleControl()
            }
            .disabled(year <= earliestYear)
            .opacity(year <= earliestYear ? 0.25 : 1)
            Spacer()
            Text(String(year))
                .font(.system(.title, design: .rounded).weight(.bold))
                .contentTransition(.numericText())
            Spacer()
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { yearOffset += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .liquidGlassCircleControl()
            }
            .disabled(yearOffset >= 0)
            .opacity(yearOffset >= 0 ? 0.25 : 1)
        }
        .padding(.horizontal)
    }
}
