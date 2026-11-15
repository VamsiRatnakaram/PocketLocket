import Foundation

/// The headline a widget shows for the metric the user picked.
///
/// Kept apart from the layout so small / medium / large / Lock Screen all read
/// the same sentence for the same data, and so the wording can be unit-tested
/// without rendering anything.
struct WidgetReadout: Equatable {
    let headline: String
    let caption: String
    /// True when the number should be drawn in the "you've gone past it" colours.
    let isOver: Bool
    /// False when there is no budget to measure against, which is a different
    /// empty state from "you have spent nothing".
    let hasBudget: Bool

    init(snapshot: WidgetSnapshot, metric: WidgetMetric, now: Date = Date()) {
        let code = snapshot.isoCurrencyCode
        hasBudget = snapshot.hasBudget
        isOver = snapshot.isOverBudget

        var headline: String
        var caption: String

        switch metric {
        case .percent:
            headline = snapshot.fraction.map { WidgetText.percent(max(0, $0)) } ?? "—"
            caption = "of \(WidgetText.month(snapshot.monthStart)) budget"

        case .remaining:
            if snapshot.hasBudget {
                headline = WidgetText.money(abs(snapshot.remaining), code: code)
                caption = snapshot.isOverBudget ? "over budget" : "left"
            } else {
                headline = WidgetText.money(snapshot.totalSpent, code: code)
                caption = "spent, no budget set"
            }

        case .safeToSpend:
            if let allowance = snapshot.safeToSpend {
                headline = WidgetText.money(allowance, code: code)
                caption = "a day left"
            } else {
                headline = "—"
                caption = "set a budget to see this"
            }
        }

        // A widget can't recompute mid-month, so when the app hasn't run in a
        // while the caption says so instead of presenting a stale figure as
        // today's.
        if snapshot.isStale(now: now) {
            caption = "as of \(WidgetText.age(snapshot, now: now))"
        }

        self.headline = headline
        self.caption = caption
    }
}
