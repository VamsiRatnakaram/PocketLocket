import Foundation
import WidgetKit

/// Writes the widget's snapshot and asks WidgetKit to redraw.
///
/// The app owns every write. WidgetKit imposes a per-widget reload budget that
/// an app cannot raise, so a timeline that refreshes itself every few minutes
/// gets throttled into silence; the reliable path is the app calling
/// `reloadTimelines` when its own data actually changed. The provider's periodic
/// policy is only a stale-timestamp fallback for when the app isn't opened.
enum WidgetSnapshotStore {
    static let key = "widgetSnapshot"

    /// Publishes `snapshot`, skipping the reload when nothing visible changed.
    ///
    /// Home recomputes its month summary on several unrelated triggers (tab
    /// changes, a re-render after a sheet dismisses), and each one would
    /// otherwise spend a real reload for an identical widget. Comparing the
    /// encoded bytes rather than the struct also catches a currency or budget
    /// edit that leaves the totals alone.
    @discardableResult
    static func publish(
        _ snapshot: WidgetSnapshot,
        to defaults: UserDefaults = AppGroup.defaults,
        reload: Bool = true
    ) -> Bool {
        guard let data = snapshot.encoded() else { return false }

        // The timestamp moves with every build, so the raw bytes almost always
        // differ; compare the content a user can actually see before deciding
        // to spend a reload on an identical widget.
        if let previous = WidgetSnapshot.load(from: defaults),
           previous.sameVisibleContent(as: snapshot) {
            return false
        }

        defaults.set(data, forKey: key)
        if reload { reloadWidgets() }
        return true
    }

    /// Drops the snapshot, for *Settings → Reset local data*. Without this the
    /// widget keeps showing last month's figures after the user has wiped the
    /// app and been told their data is gone.
    static func clear(defaults: UserDefaults = AppGroup.defaults, reload: Bool = true) {
        defaults.removeObject(forKey: key)
        if reload { reloadWidgets() }
    }

    static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// True when a redraw would show the same thing.
    ///
    /// Deliberately ignores `updatedAt`: "the app ran 4 minutes ago and nothing
    /// changed" is not news, and reloading for it burns budget that a real
    /// spending event will need.
    @discardableResult
    static func publish(
        items: [SpendItem],
        monthlyBudget: Double,
        monthStart: Date,
        calendar: Calendar = .current,
        now: Date = Date(),
        categoryBudgets: [SpendCategory: Double] = [:],
        safeToSpendFocus: Set<SpendCategory> = [],
        isoCurrencyCode: String = "USD",
        showsAmounts: Bool = false,
        to defaults: UserDefaults = AppGroup.defaults
    ) -> Bool {
        let snapshot = WidgetSnapshot.build(
            items: items,
            monthlyBudget: monthlyBudget,
            monthStart: monthStart,
            now: now,
            calendar: calendar,
            categoryBudgets: categoryBudgets,
            safeToSpendFocus: safeToSpendFocus,
            isoCurrencyCode: isoCurrencyCode,
            showsAmounts: showsAmounts
        )
        return publish(snapshot, to: defaults)
    }
}

extension WidgetSnapshot {
    /// Everything a user can perceive on the widget, ignoring the timestamp.
    func sameVisibleContent(as other: WidgetSnapshot) -> Bool {
        monthStart == other.monthStart
            && totalSpent == other.totalSpent
            && monthlyBudget == other.monthlyBudget
            && categories == other.categories
            && fraction == other.fraction
            && safeToSpend == other.safeToSpend
            && isoCurrencyCode == other.isoCurrencyCode
            && showsAmounts == other.showsAmounts
    }
}
