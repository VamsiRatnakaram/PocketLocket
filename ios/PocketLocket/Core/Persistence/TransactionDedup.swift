import Foundation
import SwiftData

/// Cross-source de-duplication. The same real transaction can arrive from
/// SimpleFIN (`sf-…`) and from an imported statement (`ofx-…` / `csv-…`) with
/// different ids. We collapse those by a fuzzy signature (day + amount +
/// normalized name) so backfilling old statements that overlap your SimpleFIN
/// window doesn't double-count. Duplicates *within* one source keep their
/// distinct ids and are never merged.
@MainActor
enum TransactionDedup {
    static func source(of id: String) -> String {
        String(id.prefix(while: { $0 != "-" }))
    }

    static func key(date: Date, amount: Double, name: String) -> String {
        let day = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        let cents = Int((amount * 100).rounded())
        let normalized = String(name.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(20))
        return "\(day)|\(cents)|\(normalized)"
    }

    /// A map of dedupe-key -> source built from all existing transactions.
    static func index(_ context: ModelContext) -> [String: String] {
        let all = (try? context.fetch(FetchDescriptor<TransactionRecord>())) ?? []
        var map: [String: String] = [:]
        for txn in all {
            map[key(date: txn.date, amount: txn.amount, name: txn.merchantName ?? txn.name)] =
                source(of: txn.plaidTransactionId)
        }
        return map
    }

    /// True when an equivalent transaction from a *different* source already exists.
    static func isCrossSourceDuplicate(
        id: String, date: Date, amount: Double, name: String, in index: [String: String]
    ) -> Bool {
        guard let existingSource = index[key(date: date, amount: amount, name: name)] else { return false }
        return existingSource != source(of: id)
    }
}
