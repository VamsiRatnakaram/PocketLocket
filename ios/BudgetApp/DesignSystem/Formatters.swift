import Foundation

/// Currency / date formatting helpers.
enum CurrencyFormatter {
    static func string(_ value: Double, code: String = "USD") -> String {
        value.formatted(.currency(code: code))
    }

    /// Whole-dollar formatting for compact labels.
    static func compact(_ value: Double, code: String = "USD") -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(0)))
    }
}

enum DateParser {
    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Parses a Plaid `YYYY-MM-DD` string (ignores any time component).
    static func date(from string: String) -> Date {
        ymd.date(from: String(string.prefix(10))) ?? Date()
    }
}
