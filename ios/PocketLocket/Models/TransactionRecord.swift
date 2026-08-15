import Foundation
import SwiftData

/// Local record of a transaction, stored on-device (SimpleFIN / imported).
@Model
final class TransactionRecord {
    @Attribute(.unique) var id: String
    var plaidTransactionId: String
    var name: String
    var merchantName: String?
    var amount: Double
    var isoCurrencyCode: String
    var date: Date
    var pending: Bool
    var categoryPrimary: String?
    var categoryDetailed: String?
    var logoURL: String?
    var accountId: String?
    /// Set when this transaction was matched to a balancing leg on another of
    /// your accounts (e.g. a credit card payoff). Nil when unmatched. Recomputed
    /// idempotently after every sync by `TransferMatchService`.
    var transferPairId: String?
    /// A category chosen for *this transaction only*, overriding rules and
    /// heuristics. Needed because some descriptors are genuinely ambiguous per
    /// transaction — a Venmo can be your half of dinner one week and repaying a
    /// friend the next, and no merchant-level rule can express both.
    var categoryOverrideRaw: String?

    init(
        id: String,
        plaidTransactionId: String,
        name: String,
        merchantName: String?,
        amount: Double,
        isoCurrencyCode: String,
        date: Date,
        pending: Bool,
        categoryPrimary: String?,
        categoryDetailed: String?,
        logoURL: String?,
        accountId: String?,
        transferPairId: String? = nil,
        categoryOverrideRaw: String? = nil
    ) {
        self.id = id
        self.plaidTransactionId = plaidTransactionId
        self.name = name
        self.merchantName = merchantName
        self.amount = amount
        self.isoCurrencyCode = isoCurrencyCode
        self.date = date
        self.pending = pending
        self.categoryPrimary = categoryPrimary
        self.categoryDetailed = categoryDetailed
        self.logoURL = logoURL
        self.accountId = accountId
        self.transferPairId = transferPairId
        self.categoryOverrideRaw = categoryOverrideRaw
    }

    /// The per-transaction override, if one was set.
    var categoryOverride: SpendCategory? {
        get { categoryOverrideRaw.flatMap(SpendCategory.init(rawValue:)) }
        set { categoryOverrideRaw = newValue?.rawValue }
    }

    var category: SpendCategory {
        CategoryMapper.map(primary: categoryPrimary, detailed: categoryDetailed)
    }

    var title: String {
        if let merchantName, !merchantName.isEmpty { return merchantName }
        return name
    }
}
