import SwiftUI
import SwiftData

/// Finds likely recurring charges (streaming, gym, software, memberships…) and
/// estimates their monthly cost. Reached from the Save tab. Respects the account
/// include/exclude filter.
struct SubscriptionsView: View {
    @Query private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
    @AppStorage(SpendingAccountFilter.key) private var excludedAccountsRaw = ""

    init() {
        let cutoff = Calendar.current.date(byAdding: .month, value: -13, to: Date()) ?? .distantPast
        _transactions = Query(
            filter: #Predicate<TransactionRecord> { $0.date >= cutoff },
            sort: \TransactionRecord.date,
            order: .reverse
        )
    }

    struct Sub: Identifiable {
        let id: String
        let merchant: String
        let amount: Double
        let lastDate: Date
        let category: SpendCategory
        let count: Int
        /// Median days between consecutive charges of this merchant, or `nil`
        /// if there's only one observed charge (not enough data to tell).
        let averageIntervalDays: Double?

        /// Classifies cadence from occurrence count within the 13-month
        /// query window: a subscription billed only once in that window is
        /// treated as yearly (it hasn't recurred within the year yet); any
        /// merchant billed 2+ times is treated as monthly. This matches how
        /// subscriptions actually work in practice — a genuine yearly plan
        /// bills once, a genuine monthly plan bills repeatedly — without
        /// needing a raw count threshold that fails with limited sync history.
        var monthlyEquivalent: Double { count >= 2 ? amount : amount / 12 }
        var cadence: String { count >= 2 ? "monthly" : "yearly" }
    }

    private var subscriptions: [Sub] {
        let excluded = SpendingAccountFilter.excludedIds(from: excludedAccountsRaw)
        let recurring = transactions.filter { txn in
            txn.amount > 0
                && SpendingAccountFilter.isIncluded(txn.accountId, excluded: excluded)
                && MerchantHeuristics.isLikelySubscription((txn.merchantName ?? "") + " " + txn.name)
        }
        var byMerchant: [String: [TransactionRecord]] = [:]
        for txn in recurring { byMerchant[txn.title, default: []].append(txn) }
        return byMerchant.compactMap { merchant, txns -> Sub? in
            guard let latest = txns.max(by: { $0.date < $1.date }) else { return nil }
            let sorted = txns.sorted { $0.date < $1.date }
            let averageIntervalDays: Double?
            if sorted.count >= 2 {
                let totalSpan = sorted.last!.date.timeIntervalSince(sorted.first!.date)
                averageIntervalDays = (totalSpan / Double(sorted.count - 1)) / 86_400
            } else {
                averageIntervalDays = nil
            }
            return Sub(
                id: merchant, merchant: merchant, amount: latest.amount, lastDate: latest.date,
                category: latest.resolvedCategory(using: rules), count: txns.count,
                averageIntervalDays: averageIntervalDays
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
