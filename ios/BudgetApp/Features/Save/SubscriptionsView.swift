import SwiftUI
import SwiftData

/// Finds likely recurring charges (streaming, gym, software, memberships…) and
/// estimates their monthly cost. Reached from the Save tab. Respects the account
/// include/exclude filter.
struct SubscriptionsView: View {
    @Query(sort: \TransactionRecord.date, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
    @AppStorage(SpendingAccountFilter.key) private var excludedAccountsRaw = ""

    struct Sub: Identifiable {
        let id: String
        let merchant: String
        let amount: Double
        let lastDate: Date
        let category: SpendCategory
        let count: Int
        /// Roughly monthly (≥6 hits/yr) counts fully; rarer ones look annual.
        var monthlyEquivalent: Double { count >= 6 ? amount : amount / 12 }
        var cadence: String { count >= 6 ? "monthly" : "yearly" }
    }

    private var subscriptions: [Sub] {
        let excluded = SpendingAccountFilter.excludedIds(from: excludedAccountsRaw)
        let cutoff = Calendar.current.date(byAdding: .month, value: -13, to: Date()) ?? .distantPast
        let recurring = transactions.filter { txn in
            txn.date >= cutoff
                && txn.amount > 0
                && SpendingAccountFilter.isIncluded(txn.accountId, excluded: excluded)
                && MerchantHeuristics.isLikelySubscription((txn.merchantName ?? "") + " " + txn.name)
        }
        var byMerchant: [String: [TransactionRecord]] = [:]
        for txn in recurring { byMerchant[txn.title, default: []].append(txn) }
        return byMerchant.compactMap { merchant, txns -> Sub? in
            guard let latest = txns.max(by: { $0.date < $1.date }) else { return nil }
            return Sub(
                id: merchant, merchant: merchant, amount: latest.amount, lastDate: latest.date,
                category: latest.resolvedCategory(using: rules), count: txns.count
            )
        }
        .sorted { $0.monthlyEquivalent > $1.monthlyEquivalent }
    }

    private var monthlyTotal: Double {
        subscriptions.reduce(0) { $0 + $1.monthlyEquivalent }
    }

    var body: some View {
        List {
            if !subscriptions.isEmpty {
                Section {
                    HStack {
                        Text("Estimated monthly")
                        Spacer()
                        Text(CurrencyFormatter.string(monthlyTotal))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                } footer: {
                    Text("Detected from recurring charges over the last year. Yearly plans are shown as a monthly equivalent.")
                }

                Section {
                    ForEach(subscriptions) { sub in
                        HStack(spacing: 12) {
                            Image(systemName: sub.category.symbol)
                                .foregroundStyle(sub.category.tint)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sub.merchant).lineLimit(1)
                                Text("\(sub.cadence.capitalized) • last \(sub.lastDate, format: .dateTime.month().day())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(CurrencyFormatter.string(sub.amount))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle("Subscriptions")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if subscriptions.isEmpty {
                ContentUnavailableView(
                    "No subscriptions found",
                    systemImage: "arrow.triangle.2.circlepath",
                    description: Text("Recurring charges like streaming, gym, or software will show up here.")
                )
            }
        }
    }
}
