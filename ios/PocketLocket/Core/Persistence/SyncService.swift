import Foundation
import SwiftData
import LocalAuthentication

/// On-device sync. Pulls fresh accounts + transactions directly from the
/// SimpleFIN Bridge and writes them into SwiftData. No backend is involved; the
/// device is the sole source of truth.
@MainActor
final class SyncService {
    static let shared = SyncService()

    /// Set from the app unlock so reading the biometric-protected SimpleFIN token
    /// can reuse that authentication instead of prompting again.
    var authContext: LAContext?

    private var inFlight: Task<Void, Error>?

    /// Coalesces concurrent syncs.
    ///
    /// `refreshSimpleFIN` snapshots the local ledger into a dedupe index and
    /// *then* awaits the network. A pull-to-refresh landing on top of an
    /// automatic sync therefore ran a second pass whose snapshot predated the
    /// first pass's writes, so dedupe could miss and the same transaction
    /// could be inserted twice. Later callers now join the running sync.
    func refresh(context: ModelContext) async throws {
        if let inFlight {
            return try await inFlight.value
        }
        // The task clears its own handle so the slot is held for as long as the
        // work actually runs. Clearing it where this call returns would release
        // it early whenever the caller is cancelled — the unstructured task
        // keeps going, and a fresh sync could start alongside it.
        let task = Task {
            defer { self.inFlight = nil }
            try await self.refreshSimpleFIN(context: context)
            // After new rows land, re-pair transfers across the whole history:
            // the two legs of a card payoff routinely arrive in different syncs.
            try TransferMatchService.recompute(in: context)
        }
        inFlight = task
        try await task.value
    }

    private func refreshSimpleFIN(context: ModelContext) async throws {
        guard let accessURL = SimpleFINStore.accessURL(context: authContext) else { return }
        // Request as far back as SimpleFIN/most banks will actually return
        // (omitting start-date defaults to only the last 30 days, which is
        // why history was capped short). Most bridges cap real history at
        // 12-24mo regardless, so ask generously; SimpleFIN just returns
        // whatever the underlying bank actually has.
        let since = Calendar.current.date(byAdding: .month, value: -24, to: Date())
        let set = try await SimpleFINClient().fetchAccounts(accessURL: accessURL, since: since)

        let localTransactions = try context.fetch(FetchDescriptor<TransactionRecord>())
        var transactionsByID = Dictionary(uniqueKeysWithValues: localTransactions.map { ($0.id, $0) })
        var dedupeIndex = TransactionDedup.index(localTransactions)
        let localAccounts = try context.fetch(FetchDescriptor<AccountRecord>())
        var accountsByID = Dictionary(uniqueKeysWithValues: localAccounts.map { ($0.id, $0) })
        for account in set.accounts {
            let accountId = "sf-" + account.id
            upsertLocalAccount(
                id: accountId,
                name: account.name ?? "Account",
                balance: Double(account.balance ?? "") ?? 0,
                currency: account.currency ?? "USD",
                type: SimpleFINMapper.inferType(name: account.name),
                accountsByID: &accountsByID,
                context: context
            )
            for txn in account.transactions ?? [] {
                // SimpleFIN transaction ids can repeat across accounts, so namespace them.
                upsertLocalTxn(
                    id: "sf-\(account.id)-\(txn.id)",
                    name: txn.description ?? "Transaction",
                    amount: SimpleFINMapper.appAmount(from: txn.amount),
                    date: txn.posted.map { Date(timeIntervalSince1970: $0) } ?? Date(),
                    pending: txn.pending ?? false,
                    accountId: accountId,
                    currency: account.currency ?? "USD",
                    categoryPrimary: txn.category,
                    transactionsByID: &transactionsByID,
                    dedupeIndex: &dedupeIndex,
                    context: context
                )
            }
        }
        try context.save()
    }

    private func upsertLocalAccount(id: String, name: String, balance: Double, currency: String, type: String, accountsByID: inout [String: AccountRecord], context: ModelContext) {
        let existing = accountsByID[id]
        if let existing {
            existing.name = name
            existing.currentBalance = balance
            existing.isoCurrencyCode = currency
            existing.type = type
        } else {
            let account = AccountRecord(
                id: id, plaidAccountId: id, name: name, officialName: name,
                mask: nil, type: type, subtype: nil,
                currentBalance: balance, availableBalance: nil, isoCurrencyCode: currency
            )
            context.insert(account)
            accountsByID[id] = account
        }
    }

    private func upsertLocalTxn(id: String, name: String, amount: Double, date: Date, pending: Bool, accountId: String, currency: String, categoryPrimary: String?, transactionsByID: inout [String: TransactionRecord], dedupeIndex: inout [String: String], context: ModelContext) {
        let existing = transactionsByID[id]
        if let existing {
            existing.name = name
            existing.merchantName = name
            existing.amount = amount
            existing.date = date
            existing.pending = pending
            existing.accountId = accountId
            existing.isoCurrencyCode = currency
            existing.categoryPrimary = categoryPrimary
        } else {
            // Skip a transaction already imported from a statement for the same day/amount.
            if TransactionDedup.isCrossSourceDuplicate(id: id, date: date, amount: amount, name: name, in: dedupeIndex) {
                return
            }
            let transaction = TransactionRecord(
                id: id, plaidTransactionId: id, name: name, merchantName: name,
                amount: amount, isoCurrencyCode: currency, date: date, pending: pending,
                categoryPrimary: categoryPrimary, categoryDetailed: nil, logoURL: nil, accountId: accountId
            )
            context.insert(transaction)
            transactionsByID[id] = transaction
            dedupeIndex[TransactionDedup.key(date: date, amount: amount, name: name)] = TransactionDedup.source(of: id)
        }
    }
}

@MainActor
enum SimpleFINDataStore {
    static func deleteSyncedData(in context: ModelContext) throws {
        let transactions = try context.fetch(FetchDescriptor<TransactionRecord>())
        for transaction in transactions where transaction.plaidTransactionId.hasPrefix("sf-") {
            context.delete(transaction)
        }

        let accounts = try context.fetch(FetchDescriptor<AccountRecord>())
        for account in accounts where account.plaidAccountId.hasPrefix("sf-") {
            context.delete(account)
        }

        try context.save()
    }
}
