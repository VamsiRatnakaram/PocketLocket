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

        /// Classifies cadence from the observed spacing between charges
        /// rather than a raw occurrence count — a count-based threshold
        /// (e.g. "6+ hits in 13mo = monthly") falsely calls genuinely-monthly
        /// charges "yearly" when the user only has a few months of history.
        ///
        /// The monthly-equivalent amount is normalized continuously from the
        /// observed interval (rather than a binary monthly/yearly split) so
        /// quarterly and semiannual charges aren't mis-scaled by a hard
        /// cutoff, and so billing-date jitter near any single threshold
        /// can't swing the estimate by a large multiple. With only one
        /// observed charge (no interval yet), we conservatively assume
        /// yearly — same as the prior count-based default for a low
        /// occurrence count — rather than assuming monthly, since a false
        /// "monthly" wildly overstates a true annual subscription.
        var monthlyEquivalent: Double {
            guard let interval = averageIntervalDays, interval > 1 else { return amount / 12 }
            let monthsPerCharge = interval / 30.44
            return amount / max(monthsPerCharge, 1.0 / 3) // never scale up more than ~3x for very frequent charges
        }
        var cadence: String {
            guard let interval = averageIntervalDays else { return "yearly" }
            switch interval {
            case ..<45: return "monthly"
            case ..<135: return "quarterly"
            case ..<270: return "semiannual"
            default: return "yearly"
            }
        }
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
