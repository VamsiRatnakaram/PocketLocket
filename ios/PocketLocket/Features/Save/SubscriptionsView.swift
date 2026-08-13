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
                if median > 0 && mad / median > 0.5 {
                    // Gaps are too inconsistent for any single cadence to be
                    // honest — estimate a monthly rate from the total charged
                    // over the observed span instead of picking a bucket.
                    let spanDays = sorted.last!.timeIntervalSince(sorted.first!) / dayLength
                    let totalCharged = amount * Double(sorted.count) // approximation; display uses latest amount
                    let rate = spanDays > 0 ? totalCharged / spanDays * 30.44 : amount
                    return (.irregular, .confirmed, rate, false)
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
            let (cadence, confidence, monthlyEquivalent, isStale) = Sub.classify(
                dates: sorted.map(\.date), amount: latest.amount, dataHorizonDays: dataHorizonDays
            )
            return Sub(
                id: merchant, merchant: merchant, amount: latest.amount, lastDate: latest.date,
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

    private var monthlyTotal: Double {
        // Stale subscriptions are shown (so the user can see/remove them from
        // tracking) but excluded from the headline total — a cancelled
        // service shouldn't permanently inflate "Estimated monthly".
        subscriptions.filter { !$0.isStale }.reduce(0) { $0 + $1.monthlyEquivalent }
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
                    Text("Estimated from recurring charges over the last 13 months. Yearly/quarterly plans are shown as a monthly equivalent; plans seen only once are estimated, and lapsed subscriptions are excluded from the total.")
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
