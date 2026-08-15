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
        /// Bucketing on the number alone would let 500 EUR balance 500 USD and
        /// silently drop half a grand of real spending out of the budget.
        let currency: String?

        init(id: String, accountId: String, amount: Double, date: Date, currency: String? = nil) {
            self.id = id
            self.accountId = accountId
            self.amount = amount
            self.date = date
            self.currency = currency
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

    /// How far apart the two legs may post.
    ///
    /// Applied as a sliding window around each transaction rather than anchored
    /// to a calendar boundary, since a payment made near a month end would
    /// otherwise fall outside its own window.
    ///
    /// Eight days covers the realistic settlement delay — a payment initiated
    /// before a weekend or holiday can take several business days to post on
    /// both sides — while staying narrow enough that unrelated equal amounts
    /// rarely collide. Widening it much further mostly buys false positives,
    /// since the remaining guards (different accounts, a credit or loan account
    /// on one side, each leg used once) then carry all of the precision.
    static let defaultWindowInDays = 8

    /// Pairs balancing transactions, returning transaction id -> pair id.
    ///
    /// - Parameters:
    ///   - candidates: every transaction to consider (pass full history —
    ///     matching is idempotent and cheap).
    ///   - transferAccountIds: accounts where one side of a pair must live,
    ///     i.e. credit cards and loans. Requiring this is what stops a $50
    ///     purchase and an unrelated $50 refund between two checking accounts
    ///     from looking like a transfer.
    ///   - windowInDays: maximum posting gap between the legs. Defaults to an
    ///     eight-day sliding window (see `defaultWindowInDays`).
    static func match(
        candidates: [Candidate],
        transferAccountIds: Set<String>,
        windowInDays: Int = defaultWindowInDays
    ) -> [String: String] {
        // Bucket by currency and exact magnitude in cents. A transfer moves an
        // identical amount of the same currency, so only transactions sharing a
        // bucket can ever pair, and this keeps the comparison near-linear
        // instead of quadratic over all history.
        struct Bucket: Hashable {
            let currency: String
            let cents: Int
        }

        var outflows: [Bucket: [Candidate]] = [:]
        var inflows: [Bucket: [Candidate]] = [:]
        for candidate in candidates where !candidate.accountId.isEmpty {
            let cents = Int((abs(candidate.amount) * 100).rounded())
            guard cents > 0 else { continue }
            let bucket = Bucket(currency: candidate.currency?.uppercased() ?? "USD", cents: cents)
            if candidate.amount > 0 {
                outflows[bucket, default: []].append(candidate)
            } else {
                inflows[bucket, default: []].append(candidate)
            }
        }

        let window = TimeInterval(windowInDays) * 86_400
        var possibilities: [(outflow: Candidate, inflow: Candidate, distance: TimeInterval)] = []

        for (bucket, outs) in outflows {
            guard let ins = inflows[bucket] else { continue }
            for out in outs {
                for inflow in ins {
                    // Money must actually cross accounts. Two legs on the same
                    // account are a purchase and a refund, not a transfer.
                    guard out.accountId != inflow.accountId else { continue }
                    // Direction matters. Paying a card credits the *card*, so
                    // the inflow leg is the one that must sit on the credit or
                    // loan account. Accepting a credit/loan account on either
                    // side let a card purchase pair with an unrelated checking
                    // deposit and erase real spending from the budget.
                    guard transferAccountIds.contains(inflow.accountId) else { continue }
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

        // Greedy seeding: each leg belongs to at most one pair, so three $500
        // payments in a month consume three distinct credits rather than all
        // latching onto the nearest one.
        var inflowMatch: [String: String] = [:]   // inflow id -> outflow id
        var outflowMatch: [String: String] = [:]  // outflow id -> inflow id
        for possibility in possibilities {
            guard outflowMatch[possibility.outflow.id] == nil,
                  inflowMatch[possibility.inflow.id] == nil else { continue }
            outflowMatch[possibility.outflow.id] = possibility.inflow.id
            inflowMatch[possibility.inflow.id] = possibility.outflow.id
        }

        // Greedy alone is not maximal. With outflows on days 0 and 7 and
        // inflows on days 1 and -8, taking the globally closest edge (0-1)
        // strands day 7 outside the window of the only inflow left, and a real
        // payoff keeps counting as spending. Augmenting paths reassign the
        // already-matched legs so both pairs survive, which is what maximum
        // bipartite matching guarantees.
        var adjacency: [String: [String]] = [:]
        for possibility in possibilities {
            adjacency[possibility.outflow.id, default: []].append(possibility.inflow.id)
        }

        func augment(_ outflowId: String, _ visited: inout Set<String>) -> Bool {
            for inflowId in adjacency[outflowId] ?? [] {
                guard !visited.contains(inflowId) else { continue }
                visited.insert(inflowId)
                if let holder = inflowMatch[inflowId] {
                    // Freeing this inflow only works if its current owner can
                    // be re-homed; `augment` rewrites the owner's entry itself,
                    // so nothing stale is left behind.
                    guard augment(holder, &visited) else { continue }
                }
                inflowMatch[inflowId] = outflowId
                outflowMatch[outflowId] = inflowId
                return true
            }
            return false
        }

        // Deterministic order so a re-sync produces the same pairing.
        for outflowId in adjacency.keys.sorted() where outflowMatch[outflowId] == nil {
            var visited: Set<String> = []
            _ = augment(outflowId, &visited)
        }

        var assigned: [String: String] = [:]
        for (outflowId, inflowId) in outflowMatch {
            let pair = Pair(outflowId: outflowId, inflowId: inflowId)
            assigned[outflowId] = pair.id
            assigned[inflowId] = pair.id
        }
        return assigned
    }

    /// Account types whose transactions can form one side of a transfer pair.
    static func isTransferAccountType(_ type: String?) -> Bool {
        guard let type = type?.lowercased() else { return false }
        return type == "credit" || type == "loan"
    }
}
