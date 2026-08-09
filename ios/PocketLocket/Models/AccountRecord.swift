import Foundation
import SwiftData

/// Local record of a bank account, stored on-device (SimpleFIN / imported).
@Model
final class AccountRecord {
    @Attribute(.unique) var id: String
    var plaidAccountId: String
    var name: String
    var officialName: String?
    var mask: String?
    var type: String?
    var subtype: String?
    var currentBalance: Double
    var availableBalance: Double?
    var isoCurrencyCode: String

    init(
        id: String,
        plaidAccountId: String,
        name: String,
        officialName: String?,
        mask: String?,
        type: String?,
        subtype: String?,
        currentBalance: Double,
        availableBalance: Double?,
        isoCurrencyCode: String
    ) {
        self.id = id
        self.plaidAccountId = plaidAccountId
        self.name = name
        self.officialName = officialName
        self.mask = mask
        self.type = type
        self.subtype = subtype
        self.currentBalance = currentBalance
        self.availableBalance = availableBalance
        self.isoCurrencyCode = isoCurrencyCode
    }

    var displayName: String { officialName ?? name }
}
