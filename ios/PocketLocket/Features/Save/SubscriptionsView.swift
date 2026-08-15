import SwiftUI
import SwiftData

/// Finds likely recurring charges (streaming, gym, software, memberships…) and
/// estimates their monthly cost. Reached from the Save tab. Respects the account
/// include/exclude filter.
struct SubscriptionsView: View {
    @Query private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
    @Query private var reimbursementAllocations: [ReimbursementAllocation]
    @AppStorage(SpendingAccountFilter.key) private var excludedAccountsRaw = ""

    init() {
        let cutoff = Calendar.current.date(byAdding: .month, value: -13, to: Date()) ?? .distantPast
        _transactions = Query(
            filter: #Predicate<TransactionRecord> { $0.date >= cutoff },
            sort: \TransactionRecord.date,
            order: .reverse
        )
    }

    /// Classification confidence, driving whether the UI hedges the label.
    enum CadenceConfidence {
        case confirmed  // 3+ charges, clean interval
        case likely     // exactly 2 charges — one gap is still solid evidence
        case assumed    // exactly 1 charge — inferred from recency, no real interval
    }

    enum Cadence: String {
        case monthly, quarterly, semiannual, yearly
        case irregular // gaps too inconsistent for any single cadence to be honest

        var periodsPerYear: Double {
            switch self {
            case .monthly: return 12
            case .quarterly: return 4
            case .semiannual: return 2
            case .yearly: return 1
            case .irregular: return 0 // unused — irregular computes its own rate
            }
        }

        var label: String {
            switch self {
            case .monthly: return "Monthly"
            case .quarterly: return "Quarterly"
            case .semiannual: return "Semiannual"
            case .yearly: return "Yearly"
            case .irregular: return "Varies"
            }
        }
    }

    struct Sub: Identifiable {
        let id: String
        let merchant: String
        let amount: Double
        let lastDate: Date
        let category: SpendCategory
        let count: Int
        let cadence: Cadence
        let confidence: CadenceConfidence
        /// True once a charge is overdue by 2.5x its expected interval —
        /// likely cancelled. Still shown, but excluded from the total and
        /// sorted to the bottom so a long-gone subscription doesn't
        /// permanently inflate "Estimated monthly".
        let isStale: Bool
        /// Precomputed by `classify(...)` alongside `cadence`, so the label
        /// and the dollar amount can never disagree with each other.
        let monthlyEquivalent: Double

        var cadenceLabel: String {
            let base = confidence == .assumed ? "\(cadence.label) (estimated)" : cadence.label
            return isStale ? "Inactive · \(base)" : base
        }

        /// Classifies cadence + monthly-equivalent cost from a merchant's
        /// sorted charge dates/amounts within the tracked window.
        ///
        /// - With 2+ charges, the **median** gap between consecutive charges
        ///   (not the mean span) drives classification, so one skipped or
        ///   backfilled cycle doesn't skew the result. Gaps are bucketed by
        ///   *log-spaced* boundaries (~1.7x from each anchor) rather than
        ///   fixed day ranges, because billing-date jitter is a fixed number
        ///   of days but its significance is proportional to the cadence
        ///   (3 days matters at a 30-day cadence, not at a 365-day one).
        /// - With exactly 1 charge, there's no interval to measure, so cadence
        ///   is inferred from how long ago it happened: a monthly subscription
        ///   would have billed again well within 45 days if it were going to,
        ///   so a *recent* lone charge is assumed monthly, while an *old* lone
        ///   charge (no repeat despite ample time to) is assumed yearly. This
        ///   avoids the two failure modes seen in prior attempts: assuming
        ///   yearly by default understates a brand-new monthly subscription
        ///   by ~12x (the original bug), while assuming monthly by default
        ///   overstates an annual plan by ~12x. Erring toward the shorter
        ///   cadence only when there's too little sync history to have seen
        ///   a second charge yet (dataHorizonDays < 45) avoids the former;
        ///   the recency ladder otherwise avoids the latter.
        static func classify(
            dates: [Date], amount: Double, dataHorizonDays: Int, now: Date = Date()
        ) -> (cadence: Cadence, confidence: CadenceConfidence, monthlyEquivalent: Double, isStale: Bool) {
            let sorted = dates.sorted()
            let dayLength: TimeInterval = 86_400

            func bucket(_ gapDays: Double) -> Cadence {
                switch gapDays {
                case ..<53: return .monthly       // real ~30-day billing lands 26-35 days apart
                case ..<129: return .quarterly    // real ~91-day billing lands well inside this band
                case ..<258: return .semiannual   // real ~183-day billing lands well inside this band
                default: return .yearly           // real ~365-day billing never approaches 258
                }
            }

            /// Charges per unit time, converted to a monthly rate.
            ///
            /// The span between `n` charges contains `n - 1` renewal intervals,
            /// not `n`. Dividing the full `n × amount` by the span overstated
            /// the rate by 50% for three charges and 100% for two.
            func irregularMonthlyRate(_ sorted: [Date], amount: Double, dayLength: TimeInterval) -> Double {
                let spanDays = sorted.last!.timeIntervalSince(sorted.first!) / dayLength
                guard spanDays > 0, sorted.count > 1 else { return amount }
                return amount * Double(sorted.count - 1) / spanDays * 30.44
            }

            func stale(expectedIntervalDays: Double) -> Bool {
                now.timeIntervalSince(sorted.last ?? now) / dayLength > expectedIntervalDays * 2.5
            }

            if sorted.count >= 3 {
                var gaps: [Double] = []
                for i in 1..<sorted.count {
                    gaps.append(sorted[i].timeIntervalSince(sorted[i - 1]) / dayLength)
                }
                let sortedGaps = gaps.sorted()
                let median = sortedGaps.count % 2 == 1
                    ? sortedGaps[sortedGaps.count / 2]
                    : (sortedGaps[sortedGaps.count / 2 - 1] + sortedGaps[sortedGaps.count / 2]) / 2
                let deviations = gaps.map { abs($0 - median) }.sorted()
                let mad = deviations.count % 2 == 1
                    ? deviations[deviations.count / 2]
                    : (deviations[deviations.count / 2 - 1] + deviations[deviations.count / 2]) / 2
                // Two gaps have no meaningful median: an average of two
                // numbers that disagree is a value neither of them supports.
                // Quarterly billing with one skipped cycle (91 and 182 days)
                // averaged to 136.5 and was confidently reported as
                // semiannual, halving the merchant's monthly equivalent. When
                // the longer gap is close to a whole multiple of the shorter
                // one, the shorter gap is the real cadence and the long gap is
                // the skipped cycles.
                if gaps.count == 2 {
                    let short = min(gaps[0], gaps[1])
                    let long = max(gaps[0], gaps[1])
                    if short > 0 {
                        let multiple = long / short
                        let nearest = multiple.rounded()
                        if nearest >= 1, abs(multiple - nearest) <= 0.15 {
                            let cadence = bucket(short)
                            return (cadence, .confirmed, amount * cadence.periodsPerYear / 12,
                                    stale(expectedIntervalDays: short))
                        }
                    }
                    return (.irregular, .likely, irregularMonthlyRate(sorted, amount: amount, dayLength: dayLength),
                            stale(expectedIntervalDays: long))
                }

                if median > 0 && mad / median > 0.5 {
                    // Gaps are too inconsistent for any single cadence to be
                    // honest — estimate a monthly rate from the total charged
                    // over the observed span instead of picking a bucket.
                    // Staleness still applies: an irregular merchant that
                    // stopped charging a year ago was previously pinned into
                    // "Estimated monthly" forever, because this path hard-coded
                    // `false`.
                    return (.irregular, .confirmed,
                            irregularMonthlyRate(sorted, amount: amount, dayLength: dayLength),
                            stale(expectedIntervalDays: median))
                }
                let cadence = bucket(median)
                return (cadence, .confirmed, amount * cadence.periodsPerYear / 12, stale(expectedIntervalDays: median))
            }

            if sorted.count == 2 {
                let gap = sorted[1].timeIntervalSince(sorted[0]) / dayLength
                let cadence = bucket(gap)
                return (cadence, .likely, amount * cadence.periodsPerYear / 12, stale(expectedIntervalDays: gap))
            }

            // Exactly one charge: infer from recency, with a guard for
            // brand-new sync history where a second charge hasn't had time
            // to appear yet regardless of true cadence.
            let ageDays = now.timeIntervalSince(sorted[0]) / dayLength
            let cadence: Cadence
            if dataHorizonDays < 45 || ageDays <= 45 {
                cadence = .monthly
            } else if ageDays <= 100 {
                cadence = .quarterly
            } else if ageDays <= 200 {
                cadence = .semiannual
            } else {
                cadence = .yearly
            }
            return (cadence, .assumed, amount * cadence.periodsPerYear / 12, false)
        }
    }

    private var subscriptions: [Sub] {
        let excluded = SpendingAccountFilter.excludedIds(from: excludedAccountsRaw)
        let reimbursementIndex = ReimbursementAllocationIndex(reimbursementAllocations)
        let recurring = transactions.filter { txn in
            txn.amount > 0
                && SpendingAccountFilter.isIncluded(txn.accountId, excluded: excluded)
                && MerchantHeuristics.isLikelySubscription((txn.merchantName ?? "") + " " + txn.name)
        }
        // How much history we've actually synced (oldest transaction of any
        // kind, not just this merchant) — a merchant with only one charge
        // can't be assumed to have a longer cadence than we've had time to
        // observe a second charge for.
        let dataHorizonDays = transactions.last.map {
            max(0, Int(Date().timeIntervalSince($0.date) / 86_400))
        } ?? 0
        var byMerchant: [String: [TransactionRecord]] = [:]
        for txn in recurring { byMerchant[txn.title, default: []].append(txn) }
        return byMerchant.compactMap { merchant, txns -> Sub? in
            guard let latest = txns.max(by: { $0.date < $1.date }) else { return nil }
            let sorted = txns.sorted { $0.date < $1.date }
            let effectiveLatestAmount = reimbursementIndex.effectiveExpenseAmount(
                transactionID: latest.id,
                originalAmount: latest.amount
            )
            let (cadence, confidence, monthlyEquivalent, isStale) = Sub.classify(
                dates: sorted.map(\.date),
                amount: effectiveLatestAmount,
                dataHorizonDays: dataHorizonDays
            )
            return Sub(
                id: merchant,
                merchant: merchant,
                amount: effectiveLatestAmount,
                lastDate: latest.date,
                category: latest.resolvedCategory(using: rules), count: txns.count,
                cadence: cadence, confidence: confidence, isStale: isStale,
                monthlyEquivalent: monthlyEquivalent
            )
        }
        // Stale (likely-cancelled) subscriptions sort to the bottom regardless
        // of their historical amount, since they're no longer active spend.
        .sorted {
            if $0.isStale != $1.isStale { return !$0.isStale }
            return $0.monthlyEquivalent > $1.monthlyEquivalent
        }
    }

    private func monthlyTotal(_ subscriptions: [Sub]) -> Double {
        // Stale subscriptions are shown (so the user can see/remove them from
        // tracking) but excluded from the headline total — a cancelled
        // service shouldn't permanently inflate "Estimated monthly".
        // `.assumed` rows are a single charge with no observed interval, so
        // their cadence is a guess. A $119.88 annual plan seen once was
        // guessed monthly and added $119.88 to the headline every month. The
        // row still shows its estimate; it just doesn't get to claim a place
        // in the total until a second charge proves the cadence.
        subscriptions
            .filter { !$0.isStale && $0.confidence != .assumed }
            .reduce(0) { $0 + $1.monthlyEquivalent }
    }

    var body: some View {
        content(subscriptions)
    }

    private func content(_ subscriptions: [Sub]) -> some View {
        List {
            if !subscriptions.isEmpty {
                Section {
                    HStack {
                        Text("Estimated monthly")
                        Spacer()
                        Text(CurrencyFormatter.string(monthlyTotal(subscriptions)))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                } footer: {
                    Text("Estimated from recurring charges over the last 13 months. Yearly/quarterly plans are shown as a monthly equivalent; plans seen only once are estimated and are left out of the total until a second charge confirms the cadence, and lapsed subscriptions are excluded too.")
                }

                Section {
                    ForEach(subscriptions) { sub in
                        HStack(spacing: 12) {
                            Image(systemName: sub.category.symbol)
                                .foregroundStyle(sub.category.tint)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sub.merchant).lineLimit(1)
                                Text("\(sub.cadenceLabel) • last \(sub.lastDate, format: .dateTime.month().day())")
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
