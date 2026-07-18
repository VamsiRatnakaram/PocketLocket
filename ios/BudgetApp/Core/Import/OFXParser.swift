import Foundation

/// Minimal OFX / QFX (SGML) parser for bank & credit-card statement downloads.
/// Runs fully on-device — no network, no third party. Extracts transactions and
/// the ledger balance.
struct OFXStatement {
    struct Txn {
        let fitId: String
        let date: Date
        /// App convention: positive = spend (an OFX debit is negative TRNAMT).
        let amount: Double
        let name: String
        let type: String?
    }

    let accountId: String?
    let ledgerBalance: Double?
    let currency: String?
    let transactions: [Txn]
}

enum OFXParser {
    static func parse(_ text: String) -> OFXStatement {
        let accountId = firstTag("ACCTID", in: text)
        let currency = firstTag("CURDEF", in: text)
        let ledger = tagInside("LEDGERBAL", tag: "BALAMT", in: text).flatMap(amountValue)

        var txns: [OFXStatement.Txn] = []
        for block in blocks("STMTTRN", in: text) {
            let blockString = String(block)
            guard
                let amtStr = firstTag("TRNAMT", in: blockString),
                let amt = amountValue(amtStr)
            else { continue }

            let fit = firstTag("FITID", in: blockString) ?? UUID().uuidString
            let date = firstTag("DTPOSTED", in: blockString).flatMap(parseDate) ?? Date()
            let name = firstTag("NAME", in: blockString)
                ?? firstTag("MEMO", in: blockString)
                ?? "Transaction"
            let type = firstTag("TRNTYPE", in: blockString)

            // OFX: negative TRNAMT = money out (spend). App: positive = spend.
            txns.append(.init(fitId: fit, date: date, amount: -amt, name: decodeEntities(name), type: type))
        }

        return OFXStatement(
            accountId: accountId,
            ledgerBalance: ledger,
            currency: currency,
            transactions: txns
        )
    }

    // MARK: - SGML helpers

    /// Reads the value after `<TAG>` up to the next `<` or line break (OFX leaf
    /// elements are not closed).
    private static func firstTag(_ tag: String, in text: String) -> String? {
        guard let range = text.range(of: "<\(tag)>", options: .caseInsensitive) else { return nil }
        let value = text[range.upperBound...].prefix { $0 != "<" && $0 != "\n" && $0 != "\r" }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Returns all substrings inside `<TAG>…</TAG>` aggregate blocks.
    private static func blocks(_ tag: String, in text: String) -> [Substring] {
        var result: [Substring] = []
        let open = "<\(tag)>"
        var start = text.startIndex
        while let openRange = text.range(of: open, options: .caseInsensitive, range: start..<text.endIndex) {
            let closeRange = text.range(of: "</\(tag)>", options: .caseInsensitive, range: openRange.upperBound..<text.endIndex)
            let end = closeRange?.lowerBound ?? text.endIndex
            result.append(text[openRange.upperBound..<end])
            start = closeRange?.upperBound ?? text.endIndex
        }
        return result
    }

    private static func tagInside(_ container: String, tag: String, in text: String) -> String? {
        guard let range = text.range(of: "<\(container)>", options: .caseInsensitive) else { return nil }
        return firstTag(tag, in: String(text[range.upperBound...]))
    }

    private static func parseDate(_ raw: String) -> Date? {
        let digits = raw.prefix(8)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: String(digits))
    }

    private static func amountValue(_ raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }

    private static func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespaces)
    }
}
