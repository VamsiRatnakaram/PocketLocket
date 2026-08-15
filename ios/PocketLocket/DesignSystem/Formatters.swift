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

    /// Formatting for the donut's center readout, which is a fixed-width hole
    /// in the middle of a ring: text that outgrows it either shrinks to
    /// unreadable or collides with the ring itself.
    ///
    /// So it drops the cents -- nobody budgets to the penny, and ".00" was
    /// spending three of the available characters to say nothing -- and caps
    /// the result at six digits, past which it abbreviates rather than
    /// overflowing.
    ///
    /// Deliberately separate from `compact`: this is a layout constraint of one
    /// specific view, not a general opinion about how money should be shown.
    static func ringCenter(_ value: Double, code: String = "USD") -> String {
        let magnitude = abs(value.rounded())
        let sign = value.rounded() < 0 ? "-" : ""

        // Six digits covers everything below 1,000,000.
        if magnitude < 1_000_000 {
            return compact(value, code: code)
        }

        let (scaled, suffix): (Double, String) = magnitude >= 1_000_000_000_000
            ? (magnitude / 1_000_000_000_000, "T")
            : magnitude >= 1_000_000_000
                ? (magnitude / 1_000_000_000, "B")
                : (magnitude / 1_000_000, "M")

        // One decimal place only while it fits: 1.2M, but 123M rather than
        // 123.4M, so the string never exceeds six characters of number.
        let precision = scaled < 100 ? 1 : 0
        let number = scaled.formatted(.number.precision(.fractionLength(precision)))
        let symbol = Locale.current.currencySymbol ?? "$"
        return "\(sign)\(symbol)\(number)\(suffix)"
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
