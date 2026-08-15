import Foundation
import SwiftData
import CryptoKit
import CommonCrypto

/// Password-protected local backup. All data (accounts, transactions, rules) is
/// serialized to JSON, then encrypted with AES-GCM using a key derived from the
/// user's password via PBKDF2-HMAC-SHA256. The exported file contains only a
/// random salt + ciphertext, so it is useless to anyone without the password.
@MainActor
enum BackupService {

    // MARK: - Serializable shapes

    struct Payload: Codable {
        var version = 2
        var exportedAt = Date()
        var accounts: [AccountDTO]
        var transactions: [TxnDTO]
        var rules: [RuleDTO]
        /// Optional so backups created before grouping controls still decode.
        var groupingRules: [GroupingRuleDTO]?
        /// Optional so version 1 backups still decode.
        var reimbursementAllocations: [ReimbursementAllocationDTO]? = nil
    }

    struct AccountDTO: Codable {
        var id: String
        var plaidAccountId: String
        var name: String
        var officialName: String?
        var mask: String?
        var type: String?
        var typeOverrideRaw: String?
        var subtype: String?
        var currentBalance: Double
        var availableBalance: Double?
        var isoCurrencyCode: String
        init(_ a: AccountRecord) {
            id = a.id; plaidAccountId = a.plaidAccountId; name = a.name
            officialName = a.officialName; mask = a.mask; type = a.type
            typeOverrideRaw = a.typeOverrideRaw; subtype = a.subtype
            currentBalance = a.currentBalance; availableBalance = a.availableBalance
            isoCurrencyCode = a.isoCurrencyCode
        }
    }

    struct TxnDTO: Codable {
        var id: String
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
        var categoryOverrideRaw: String?
        init(_ t: TransactionRecord) {
            id = t.id; plaidTransactionId = t.plaidTransactionId; name = t.name
            merchantName = t.merchantName; amount = t.amount; isoCurrencyCode = t.isoCurrencyCode
            date = t.date; pending = t.pending; categoryPrimary = t.categoryPrimary
            categoryDetailed = t.categoryDetailed; logoURL = t.logoURL; accountId = t.accountId
            categoryOverrideRaw = t.categoryOverrideRaw
        }
    }

    struct RuleDTO: Codable {
        var matchText: String
        var categoryRaw: String
        var createdAt: Date
        init(_ r: CategoryRule) { matchText = r.matchText; categoryRaw = r.categoryRaw; createdAt = r.createdAt }
    }

    struct GroupingRuleDTO: Codable {
        var sourceKey: String
        var groupID: String?
        var groupName: String
        var createdAt: Date
        init(_ rule: MerchantGroupingRule) {
            sourceKey = rule.sourceKey
            groupID = rule.groupID
            groupName = rule.groupName
            createdAt = rule.createdAt
        }
    }

    struct ReimbursementAllocationDTO: Codable {
        var id: String
        var sourceTransactionID: String
        var expenseTransactionID: String
        var amount: Double
        var createdAt: Date

        init(_ allocation: ReimbursementAllocation) {
            id = allocation.id
            sourceTransactionID = allocation.sourceTransactionID
            expenseTransactionID = allocation.expenseTransactionID
            amount = allocation.amount
            createdAt = allocation.createdAt
        }
    }

    private struct Envelope: Codable {
        var version = 1
        var salt: String
        var data: String
    }

    enum BackupError: LocalizedError {
        case emptyPassword, keyDerivationFailed, encodeFailed, corruptFile, wrongPassword
        var errorDescription: String? {
            switch self {
            case .emptyPassword: return "Please enter a password."
            case .keyDerivationFailed: return "Could not derive an encryption key."
            case .encodeFailed: return "Could not create the backup."
            case .corruptFile: return "This doesn't look like a Budget backup file."
            case .wrongPassword: return "Wrong password, or the file is corrupted."
            }
        }
    }

    // MARK: - Public API

    static func exportEncrypted(password: String, context: ModelContext) throws -> Data {
        guard !password.isEmpty else { throw BackupError.emptyPassword }
        let payload = Payload(
            accounts: try context.fetch(FetchDescriptor<AccountRecord>()).map(AccountDTO.init),
            transactions: try context.fetch(FetchDescriptor<TransactionRecord>()).map(TxnDTO.init),
            rules: try context.fetch(FetchDescriptor<CategoryRule>()).map(RuleDTO.init),
            groupingRules: try context.fetch(FetchDescriptor<MerchantGroupingRule>()).map(GroupingRuleDTO.init),
            reimbursementAllocations: try context.fetch(
                FetchDescriptor<ReimbursementAllocation>()
            ).map(ReimbursementAllocationDTO.init)
        )
        let plaintext = try JSONEncoder().encode(payload)
        return try encrypt(plaintext, password: password)
    }

    @discardableResult
    static func importEncrypted(_ fileData: Data, password: String, context: ModelContext) throws -> Int {
        guard !password.isEmpty else { throw BackupError.emptyPassword }
        let plaintext = try decrypt(fileData, password: password)
        guard let payload = try? JSONDecoder().decode(Payload.self, from: plaintext) else {
            throw BackupError.corruptFile
        }
        do {
            return try restore(payload, into: context)
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: - Crypto

    private static func encrypt(_ plaintext: Data, password: String) throws -> Data {
        var saltBytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else {
            throw BackupError.encodeFailed
        }
        let salt = Data(saltBytes)
        let key = try deriveKey(password: password, salt: salt)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw BackupError.encodeFailed }
        let envelope = Envelope(salt: salt.base64EncodedString(), data: combined.base64EncodedString())
        return try JSONEncoder().encode(envelope)
    }

    private static func decrypt(_ fileData: Data, password: String) throws -> Data {
        guard
            let envelope = try? JSONDecoder().decode(Envelope.self, from: fileData),
            let salt = Data(base64Encoded: envelope.salt),
            let combined = Data(base64Encoded: envelope.data)
        else { throw BackupError.corruptFile }

        let key = try deriveKey(password: password, salt: salt)
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw BackupError.wrongPassword
        }
    }

    private static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        let passwordData = Data(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let result = derived.withUnsafeMutableBytes { derivedPtr in
            salt.withUnsafeBytes { saltPtr in
                passwordData.withUnsafeBytes { pwPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwPtr.baseAddress!.assumingMemoryBound(to: CChar.self),
                        passwordData.count,
                        saltPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        150_000,
                        derivedPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }
        guard Int(result) == kCCSuccess else { throw BackupError.keyDerivationFailed }
        return SymmetricKey(data: Data(derived))
    }

    // MARK: - Restore / merge

    private static func restore(_ payload: Payload, into context: ModelContext) throws -> Int {
        for a in payload.accounts {
            let pid = a.plaidAccountId
            let exists = ((try? context.fetch(
                FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.plaidAccountId == pid })
            ))?.first) != nil
            guard !exists else { continue }
            context.insert(AccountRecord(
                id: a.id, plaidAccountId: a.plaidAccountId, name: a.name,
                officialName: a.officialName, mask: a.mask, type: a.type,
                typeOverrideRaw: a.typeOverrideRaw, subtype: a.subtype,
                currentBalance: a.currentBalance, availableBalance: a.availableBalance,
                isoCurrencyCode: a.isoCurrencyCode
            ))
        }

        var insertedTxns = 0
        for t in payload.transactions {
            let pid = t.plaidTransactionId
            let exists = ((try? context.fetch(
                FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.plaidTransactionId == pid })
            ))?.first) != nil
            guard !exists else { continue }
            context.insert(TransactionRecord(
                id: t.id, plaidTransactionId: t.plaidTransactionId, name: t.name,
                merchantName: t.merchantName, amount: t.amount, isoCurrencyCode: t.isoCurrencyCode,
                date: t.date, pending: t.pending, categoryPrimary: t.categoryPrimary,
                categoryDetailed: t.categoryDetailed, logoURL: t.logoURL, accountId: t.accountId,
                categoryOverrideRaw: t.categoryOverrideRaw
            ))
            insertedTxns += 1
        }

        for r in payload.rules {
            // CategoryRule lowercases matchText on the way in, so comparing
            // the backup's raw text would miss an existing rule and insert a
            // duplicate of a unique attribute.
            let key = r.matchText.lowercased()
            let exists = ((try? context.fetch(
                FetchDescriptor<CategoryRule>(predicate: #Predicate { $0.matchText == key })
            ))?.first) != nil
            guard !exists else { continue }
            context.insert(CategoryRule(
                matchText: r.matchText,
                category: SpendCategory(rawValue: r.categoryRaw) ?? .other,
                createdAt: r.createdAt
            ))
        }

        for rule in payload.groupingRules ?? [] {
            let sourceKey = MerchantNormalizer.groupingKey(rule.sourceKey)
            let exists = ((try? context.fetch(
                FetchDescriptor<MerchantGroupingRule>(
                    predicate: #Predicate { $0.sourceKey == sourceKey }
                )
            ))?.first) != nil
            guard !exists else { continue }
            context.insert(MerchantGroupingRule(
                sourceKey: sourceKey,
                groupID: rule.groupID ?? UUID().uuidString,
                groupName: rule.groupName,
                createdAt: rule.createdAt
            ))
        }

        let existingAllocationIDs = Set(
            (try? context.fetch(FetchDescriptor<ReimbursementAllocation>()).map(\.id)) ?? []
        )
        let availableTransactionIDs = Set(
            (try? context.fetch(FetchDescriptor<TransactionRecord>()).map(\.id)) ?? []
        )
        for allocation in payload.reimbursementAllocations ?? [] {
            guard availableTransactionIDs.contains(allocation.sourceTransactionID),
                  availableTransactionIDs.contains(allocation.expenseTransactionID)
            else { continue }
            let id = allocation.id
            let exists = ((try? context.fetch(
                FetchDescriptor<ReimbursementAllocation>(
                    predicate: #Predicate { $0.id == id }
                )
            ))?.first) != nil
            guard !exists else { continue }
            context.insert(ReimbursementAllocation(
                id: allocation.id,
                sourceTransactionID: allocation.sourceTransactionID,
                expenseTransactionID: allocation.expenseTransactionID,
                amount: allocation.amount,
                createdAt: allocation.createdAt
            ))
        }

        try ReimbursementAllocationService.reconcile(
            in: context,
            preserving: existingAllocationIDs
        )
        try context.save()
        return insertedTxns
    }
}
