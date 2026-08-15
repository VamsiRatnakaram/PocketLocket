import Foundation
import SwiftData

/// Runs `TransferMatcher` over stored history and persists the results.
///
/// Deliberately recomputes across *all* transactions rather than only the ones
/// just synced: a pair's two legs often arrive in different syncs (the card
/// credit posts a day or two after the bank debit), so an incremental-only pass
/// would permanently miss the pairs that straddle a sync boundary. Matching is
/// cheap — magnitude bucketing keeps it near-linear — so a full pass is the
/// simpler and more correct option.
///
/// Idempotent: unchanged matches are not rewritten, so repeated runs don't
/// churn the store or trigger needless SwiftData republishes.
@MainActor
enum TransferMatchService {
    @discardableResult
    static func recompute(in context: ModelContext) throws -> Int {
        let transactions = try context.fetch(FetchDescriptor<TransactionRecord>())
        let accounts = try context.fetch(FetchDescriptor<AccountRecord>())

        let transferAccountIds = Set(
            accounts
                .filter { TransferMatcher.isTransferAccountType($0.type) }
                .map(\.id)
        )

        let matches: [String: String]
        if transferAccountIds.isEmpty {
            // No card or loan linked, so nothing can legitimately pair. Still
            // run the clearing pass below in case an account was unlinked or
            // retyped since the last run.
            matches = [:]
        } else {
            let candidates = transactions.compactMap { txn -> TransferMatcher.Candidate? in
                guard let accountId = txn.accountId, !accountId.isEmpty else { return nil }
                return TransferMatcher.Candidate(
                    id: txn.id,
                    accountId: accountId,
                    amount: txn.amount,
                    date: txn.date,
                    currency: txn.isoCurrencyCode
                )
            }
            matches = TransferMatcher.match(candidates: candidates, transferAccountIds: transferAccountIds)
        }

        var changed = 0
        for txn in transactions {
            let newValue = matches[txn.id]
            if txn.transferPairId != newValue {
                txn.transferPairId = newValue
                changed += 1
            }
        }
        if changed > 0 {
            try context.save()
        }
        return changed
    }
}
