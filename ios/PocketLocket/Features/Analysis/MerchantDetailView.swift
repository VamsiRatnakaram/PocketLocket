import SwiftUI
import Charts

/// Drill-down for a single merchant: visit history over time and every
/// transaction, most recent first — reuses `TransactionRow`/`TransactionDetailView`
/// from the Transactions feature for a consistent look.
struct MerchantDetailView: View {
    let stats: MerchantAnalytics.MerchantStats
    let transactions: [TransactionRecord]
    let rules: [CategoryRule]

    @State private var detail: TransactionRecord?

    private var items: [TransactionRecord] {
        transactions
            .filter {
                $0.amount > 0
                    && $0.resolvedCategory(using: rules).isSpending
                    && stats.matches($0.title)
            }
            .sorted { $0.date > $1.date }
    }

    private var monthly: [MerchantAnalytics.CategoryMonth] {
        let calendar = Calendar.current
        var buckets: [Date: Double] = [:]
        for txn in items {
            guard let monthStart = calendar.dateInterval(of: .month, for: txn.date)?.start else { continue }
            buckets[monthStart, default: 0] += txn.amount
        }
        return buckets
            .map { MerchantAnalytics.CategoryMonth(category: stats.category, monthStart: $0.key, amount: $0.value) }
            .sorted { $0.monthStart < $1.monthStart }
    }

    var body: some View {
        List {
            Section {
                summary
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if monthly.count > 1 {
                Section("Spend over time") {
                    chart
                }
            }

            Section {
                ForEach(items) { txn in
                    Button { detail = txn } label: {
                        TransactionRow(txn: txn, category: txn.resolvedCategory(using: rules))
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
            } header: {
                Text("\(items.count) transaction\(items.count == 1 ? "" : "s")")
            }
        }
        .listStyle(.plain)
        .navigationTitle(stats.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { txn in
            TransactionDetailView(txn: txn, currentCategory: txn.resolvedCategory(using: rules))
        }
    }

    private var summary: some View {
        HStack(spacing: 16) {
            statTile(title: "Visits", value: "\(stats.visitCount)")
            statTile(title: "Total", value: CurrencyFormatter.compact(stats.totalSpent))
            statTile(title: "Avg", value: CurrencyFormatter.compact(stats.averagePerVisit))
        }
        .padding(.vertical, 8)
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var chart: some View {
        Chart(monthly) { entry in
            BarMark(
                x: .value("Month", entry.monthStart, unit: .month),
                y: .value("Spent", entry.amount)
            )
            .foregroundStyle(stats.category.tint)
            .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0)))
        }
        .frame(height: 160)
    }
}
