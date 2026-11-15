import Foundation

/// One place to decide how a number is written, so the small widget, the large
/// widget and the Lock Screen row can't disagree about the same figure.
///
/// Foundation-only and shared with the app so the wording is unit-testable from
/// the app's test target and identical on both sides of the App Group.
enum WidgetText {
    /// 0.623 → "62%". No decimals: a widget is glanced at, not audited.
    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    /// Whole dollars, for headline figures where cents would be noise.
    static func money(_ value: Double, code: String) -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(0)))
    }

    /// "Mar" / "March 2026", depending on how tight the space is.
    static func month(_ date: Date, wide: Bool = false) -> String {
        wide
            ? date.formatted(.dateTime.month(.wide).year())
            : date.formatted(.dateTime.month(.abbreviated))
    }

    /// "Just now", "12m ago", "3h ago", "Yesterday"… Enough to tell "current"
    /// from "your app hasn't run in a week", without a wall of digits.
    static func age(_ snapshot: WidgetSnapshot, now: Date = Date()) -> String {
        let minutes = snapshot.ageInMinutes(now: now)
        if minutes < 1 { return "Just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return days == 1 ? "Yesterday" : "\(days)d ago"
    }
}
