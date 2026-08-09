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
        accountId: String?
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
    }

    var category: SpendCategory {
        CategoryMapper.map(primary: categoryPrimary, detailed: categoryDetailed)
    }

    var title: String {
        if let merchantName, !merchantName.isEmpty { return merchantName }
        return name
    }
}
