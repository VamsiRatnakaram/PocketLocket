import Foundation

/// User preferences that change what the widgets draw.
///
/// Stored in the App Group suite rather than the app's defaults, because the
/// widget extension reads them at render time and cannot see the app's private
/// store. `WidgetMetric` keeps its own key for the same reason.
enum WidgetPreferences {
    /// Whether widgets may show dollar amounts. Off by default: a Lock Screen is
    /// visible to whoever is standing next to you, and a percentage answers the
    /// same question without the balance.
    static let showsAmountsKey = "widgetShowAmounts"

    static func showsAmounts(from defaults: UserDefaults = AppGroup.defaults) -> Bool {
        defaults.bool(forKey: showsAmountsKey)
    }

    static func setShowsAmounts(
        _ value: Bool,
        defaults: UserDefaults = AppGroup.defaults
    ) {
        defaults.set(value, forKey: showsAmountsKey)
    }

    /// Whether the Home Screen ring is split into per-category colors.
    ///
    /// Stored inverted (`widgetMonochromeRing`) on purpose: `UserDefaults.bool`
    /// reads `false` for a key nobody ever wrote, so a plain "colorful" key
    /// would default the feature *off* — and a fresh install, or an app update
    /// before the user has opened Settings, would silently get the old grey
    /// ring. Asking for monochrome instead means "never written" is the
    /// colourful default we want.
    static let monochromeRingKey = "widgetMonochromeRing"

    static func colorfulRing(from defaults: UserDefaults = AppGroup.defaults) -> Bool {
        !defaults.bool(forKey: monochromeRingKey)
    }

    static func setColorfulRing(
        _ value: Bool,
        defaults: UserDefaults = AppGroup.defaults
    ) {
        defaults.set(!value, forKey: monochromeRingKey)
    }
}
