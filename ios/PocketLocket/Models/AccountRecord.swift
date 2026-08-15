import Foundation
import SwiftData

enum AccountTypeChoice: String, CaseIterable, Identifiable {
    case depository
    case credit
    case loan
    case investment

    var id: Self { self }

    var displayName: String {
        switch self {
        case .depository: "Depository"
        case .credit: "Credit"
        case .loan: "Loan"
        case .investment: "Investment"
        }
    }
}

/// Local record of a bank account, stored on-device (SimpleFIN / imported).
@Model
final class AccountRecord {
    @Attribute(.unique) var id: String
    var plaidAccountId: String
    var name: String
    var officialName: String?
    var mask: String?
    var type: String?
    /// User choice, kept separate so sync may refresh its inference without
    /// overwriting an explicit classification.
    var typeOverrideRaw: String?
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
        typeOverrideRaw: String? = nil,
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
        self.typeOverrideRaw = typeOverrideRaw
        self.subtype = subtype
        self.currentBalance = currentBalance
        self.availableBalance = availableBalance
        self.isoCurrencyCode = isoCurrencyCode
    }

    var displayName: String { officialName ?? name }

    var resolvedType: String? {
        typeOverrideRaw ?? type
    }
}
