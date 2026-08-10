import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Imports bank/credit-card statement files (OFX, QFX, CSV) into the local
/// SwiftData store. 100% on-device — the file never leaves the phone and no
/// third party is involved. Imported transactions are still auto-categorized by
/// the merchant heuristics (their Plaid category is nil).
@MainActor
enum ImportService {
    static var allowedTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .plainText, .text, .data]
        if let ofx = UTType(filenameExtension: "ofx") { types.append(ofx) }
        if let qfx = UTType(filenameExtension: "qfx") { types.append(qfx) }
        return types
    }

    enum ImportError: LocalizedError {
        case unreadable
        var errorDescription: String? { "Could not read that file." }
    }

    @discardableResult
    static func importFile(at url: URL, into context: ModelContext) throws -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        let text = String(decoding: data, as: UTF8.self)
        let ext = url.pathExtension.lowercased()

        let looksOFX = ext == "ofx" || ext == "qfx"
            || text.contains("<STMTTRN>")
            || text.uppercased().contains("OFXHEADER")
            || text.contains("<OFX>")

        return looksOFX
            ? importOFX(text, into: context)
            : importCSV(text, fileName: url.deletingPathExtension().lastPathComponent, into: context)
    }

    // MARK: - OFX / QFX

    private static func importOFX(_ text: String, into context: ModelContext) -> Int {
        let statement = OFXParser.parse(text)
        let currency = statement.currency ?? "USD"
        let accountId = "ofx-" + (statement.accountId ?? "imported")

        upsertAccount(
            id: accountId,
            name: "Imported (OFX)",
            balance: statement.ledgerBalance,
            currency: currency,
            context: context
        )

        let localTransactions = (try? context.fetch(FetchDescriptor<TransactionRecord>())) ?? []
        var existing = TransactionDedup.index(localTransactions)
        var existingIDs = Set(localTransactions.map(\.id))
        var inserted = 0
        for txn in statement.transactions {
            let id = "ofx-\(txn.fitId)"
            if insert(id: id, name: txn.name, amount: txn.amount, date: txn.date,
                      accountId: accountId, currency: currency, existing: &existing,
                      existingIDs: &existingIDs, context: context) {
                inserted += 1
            }
        }
        try? context.save()
        return inserted
    }

    // MARK: - CSV

    private static func importCSV(_ text: String, fileName: String, into context: ModelContext) -> Int {
        let rows = CSVParser.parse(text)
        let accountId = "csv-imported"

        upsertAccount(id: accountId, name: "Imported (CSV)", balance: nil, currency: "USD", context: context)

        let localTransactions = (try? context.fetch(FetchDescriptor<TransactionRecord>())) ?? []
        var existing = TransactionDedup.index(localTransactions)
        var existingIDs = Set(localTransactions.map(\.id))
        var inserted = 0
        for (offset, row) in rows.enumerated() {
            let stableKey = "\(Int(row.date.timeIntervalSince1970))-\(offset)-\(row.description.hashValue)"
            let id = "csv-\(stableKey)"
            if insert(id: id, name: row.description, amount: row.amount, date: row.date,
                      accountId: accountId, currency: "USD", existing: &existing,
                      existingIDs: &existingIDs, context: context) {
                inserted += 1
            }
        }
        try? context.save()
        return inserted
    }

    // MARK: - Persistence helpers

    private static func insert(
        id: String,
        name: String,
        amount: Double,
        date: Date,
        accountId: String,
        currency: String,
        existing: inout [String: String],
        existingIDs: inout Set<String>,
        context: ModelContext
    ) -> Bool {
        guard !existingIDs.contains(id) else { return false }
        // Skip the same real transaction already synced from SimpleFIN / another import.
        if TransactionDedup.isCrossSourceDuplicate(id: id, date: date, amount: amount, name: name, in: existing) {
            return false
        }

        context.insert(TransactionRecord(
            id: id,
            plaidTransactionId: id,
            name: name,
            merchantName: name,
            amount: amount,
            isoCurrencyCode: currency,
            date: date,
            pending: false,
            categoryPrimary: nil,
            categoryDetailed: nil,
            logoURL: nil,
            accountId: accountId
        ))
        existingIDs.insert(id)
        existing[TransactionDedup.key(date: date, amount: amount, name: name)] = TransactionDedup.source(of: id)
        return true
    }

    private static func upsertAccount(
        id: String,
        name: String,
        balance: Double?,
        currency: String,
        context: ModelContext
    ) {
        let existing = (try? context.fetch(
            FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.id == id })
        ))?.first

        if let existing {
            if let balance { existing.currentBalance = balance }
        } else {
            context.insert(AccountRecord(
                id: id,
                plaidAccountId: id,
                name: name,
                officialName: name,
                mask: nil,
                type: "depository",
                subtype: "imported",
                currentBalance: balance ?? 0,
                availableBalance: nil,
                isoCurrencyCode: currency
            ))
        }
    }
}
