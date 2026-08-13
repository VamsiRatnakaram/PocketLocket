import Foundation

/// Detects the two halves of a credit-card payoff (or any account-to-account
/// transfer) by looking for the balancing pair rather than trusting the
/// descriptor text.
///
/// Paying a card produces two records once both accounts are linked:
///
///   checking   +500.00   "ACH DEBIT 8829"
///   card       -500.00   "PAYMENT THANK YOU"
///
/// (App convention: positive = money out.) Today these are caught by keyword
/// matching on the descriptor, which works right up until a bank emits
/// something unhelpful like `ACH DEBIT 8829` — and then the outflow leg counts
/// as $500 of spending on top of the card purchases it's actually paying for.
///
/// A matched pair is far stronger evidence than any keyword: the money
/// demonstrably went from one of your accounts to another. It's also
/// explainable — the UI can name the account on the other side.
///
/// Pure and side-effect free so it can be tested without a database.
enum TransferMatcher {
    /// A transaction reduced to just what matching needs. `TransactionRecord`
    /// is a SwiftData `@Model`; keeping this pure keeps the logic testable.
    struct Candidate: Equatable {
        let id: String
        let accountId: String
        let amount: Double
        let date: Date

        init(id: String, accountId: String, amount: Double, date: Date) {
            self.id = id
            self.accountId = accountId
            self.amount = amount
            self.date = date
        }
    }

    struct Pair: Equatable {
        /// The leg where money left an account (positive amount).
        let outflowId: String
        /// The leg where money arrived (negative amount).
        let inflowId: String
        /// Stable across runs: derived from the two ids, so re-running the
        /// matcher over unchanged data rewrites the same value.
        var id: String {
            let (first, second) = outflowId < inflowId ? (outflowId, inflowId) : (inflowId, outflowId)
            return "pair-\(first)-\(second)"
        }
    }

    /// How far apart the two legs may post. Card payments usually clear within
    /// a couple of days; a wider window mostly buys false positives.
    static let defaultWindowInDays = 5

    /// Pairs balancing transactions, returning transaction id -> pair id.
    ///
    /// - Parameters:
    ///   - candidates: every transaction to consider (pass full history —
    ///     matching is idempotent and cheap).
    ///   - transferAccountIds: accounts where one side of a pair must live,
    ///     i.e. credit cards and loans. Requiring this is what stops a $50
    ///     purchase and an unrelated $50 refund between two checking accounts
    ///     from looking like a transfer.
    ///   - windowInDays: maximum posting gap between the legs.
    static func match(
        candidates: [Candidate],
        transferAccountIds: Set<String>,
        windowInDays: Int = defaultWindowInDays
    ) -> [String: String] {
        // Bucket by exact magnitude in cents. A transfer moves an identical
        // amount, so only transactions sharing a magnitude can ever pair, and
        // this keeps the comparison near-linear instead of quadratic over all
        // history.
        var outflows: [Int: [Candidate]] = [:]
        var inflows: [Int: [Candidate]] = [:]
        for candidate in candidates where !candidate.accountId.isEmpty {
            let cents = Int((abs(candidate.amount) * 100).rounded())
            guard cents > 0 else { continue }
            if candidate.amount > 0 {
                outflows[cents, default: []].append(candidate)
            } else {
                inflows[cents, default: []].append(candidate)
            }
        }

        let window = TimeInterval(windowInDays) * 86_400
        var possibilities: [(outflow: Candidate, inflow: Candidate, distance: TimeInterval)] = []

        for (cents, outs) in outflows {
            guard let ins = inflows[cents] else { continue }
            for out in outs {
                for inflow in ins {
                    // Money must actually cross accounts. Two legs on the same
                    // account are a purchase and a refund, not a transfer.
                    guard out.accountId != inflow.accountId else { continue }
                    guard transferAccountIds.contains(out.accountId)
                        || transferAccountIds.contains(inflow.accountId) else { continue }
                    let distance = abs(out.date.timeIntervalSince(inflow.date))
                    guard distance <= window else { continue }
                    possibilities.append((out, inflow, distance))
                }
            }
        }

        // Closest-posting pairs win. Sorting by id after distance keeps the
        // result deterministic when several candidates tie, so a re-sync can't
        // silently reshuffle which legs are considered matched.
        possibilities.sort {
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            if $0.outflow.id != $1.outflow.id { return $0.outflow.id < $1.outflow.id }
            return $0.inflow.id < $1.inflow.id
        }

        var assigned: [String: String] = [:]
        var used: Set<String> = []
        for possibility in possibilities {
            // Each leg belongs to at most one pair, so three $500 payments in a
            // month consume three distinct credits rather than all latching
            // onto the nearest one.
            guard !used.contains(possibility.outflow.id),
                  !used.contains(possibility.inflow.id) else { continue }
            let pair = Pair(outflowId: possibility.outflow.id, inflowId: possibility.inflow.id)
            assigned[possibility.outflow.id] = pair.id
            assigned[possibility.inflow.id] = pair.id
            used.insert(possibility.outflow.id)
            used.insert(possibility.inflow.id)
        }
        return assigned
    }

    /// Account types whose transactions can form one side of a transfer pair.
    static func isTransferAccountType(_ type: String?) -> Bool {
        guard let type = type?.lowercased() else { return false }
        return type == "credit" || type == "loan"
    }
}
