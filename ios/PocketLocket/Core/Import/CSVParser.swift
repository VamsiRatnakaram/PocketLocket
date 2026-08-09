import Foundation

/// Parses common bank/credit-card CSV exports fully on-device. Detects a header
/// row and maps flexible column names (date / description / amount, or separate
/// debit & credit columns).
struct CSVTxn {
    let date: Date
    let description: String
    /// App convention: positive = spend.
    let amount: Double
}

enum CSVParser {
    static func parse(_ text: String) -> [CSVTxn] {
        let rows = splitRows(text)
        guard let headerRow = rows.first else { return [] }

        let header = headerRow.map { $0.lowercased() }
        let hasHeader = header.contains { $0.contains("date") || $0.contains("amount") || $0.contains("description") }

        var dateIdx = 0, descIdx = 1, amountIdx = 2
        var debitIdx: Int?
        var creditIdx: Int?
        var start = 0

        if hasHeader {
            start = 1
            dateIdx = header.firstIndex { $0.contains("date") } ?? 0
            descIdx = header.firstIndex { $0.contains("desc") || $0.contains("name") || $0.contains("payee") || $0.contains("memo") } ?? 1
            amountIdx = header.firstIndex { $0.contains("amount") } ?? 2
            debitIdx = header.firstIndex { $0.contains("debit") || $0.contains("withdrawal") }
            creditIdx = header.firstIndex { $0.contains("credit") || $0.contains("deposit") }
        }

        var out: [CSVTxn] = []
        for row in rows[start...] {
            guard row.count > dateIdx else { continue }
            let date = parseDate(row[dateIdx]) ?? Date()
            let description = descIdx < row.count ? row[descIdx] : "Transaction"

            var amount: Double?
            if let debitIdx, let creditIdx, debitIdx < row.count, creditIdx < row.count {
                let debit = amountValue(row[debitIdx]) ?? 0
                let credit = amountValue(row[creditIdx]) ?? 0
                // Debit = spend (positive); credit = income (negative).
                amount = debit != 0 ? abs(debit) : -abs(credit)
            } else if amountIdx < row.count, let raw = amountValue(row[amountIdx]) {
                // Bank CSV: negative = money out. App: positive = spend.
                amount = -raw
            }

            guard let amount else { continue }
            out.append(CSVTxn(
                date: date,
                description: description.isEmpty ? "Transaction" : description,
                amount: amount
            ))
        }
        return out
    }

    // MARK: - Helpers

    private static func splitRows(_ text: String) -> [[String]] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(parseFields)
    }

    private static func parseFields(_ line: Substring) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var index = line.startIndex
        while index < line.endIndex {
            let char = line[index]
            if char == "\"" {
                let next = line.index(after: index)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    index = next
                } else {
                    inQuotes.toggle()
                }
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
            index = line.index(after: index)
        }
        fields.append(current)
        return fields.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static let dateFormats = [
        "yyyy-MM-dd", "MM/dd/yyyy", "M/d/yyyy", "MM/dd/yy", "dd/MM/yyyy", "yyyy/MM/dd",
    ]

    private static func parseDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    private static func amountValue(_ raw: String) -> Double? {
        var text = raw
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        var negative = false
        if text.hasPrefix("(") && text.hasSuffix(")") {
            negative = true
            text = String(text.dropFirst().dropLast())
        }
        guard let value = Double(text) else { return nil }
        return negative ? -value : value
    }
}
