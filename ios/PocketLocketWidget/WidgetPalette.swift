import SwiftUI

/// Colors for the widget.
///
/// The app's accent colour lives in the app's asset catalog, and an extension
/// gets its own catalog — which this one doesn't have. So the brand colour is
/// restated here with the same sRGB components as
/// `Assets.xcassets/AccentColor.colorset`, resolved against the widget's own
/// appearance (widgets are drawn in their own process, sometimes in dark mode
/// while the app was last seen in light).
enum WidgetPalette {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.320, green: 0.580, blue: 0.960, alpha: 1)
            : UIColor(red: 0.180, green: 0.470, blue: 0.900, alpha: 1)
    })

    /// Matches the app's ring: amber at the moment you pass budget, red for the
    /// overflow lap.
    static let overAmber = Color.orange
    static let overRed = Color.red

    /// The unfilled part of the ring, mirroring `SpendRingProgress`.
    static let track = Color.secondary.opacity(0.15)

    /// Spend the named categories don't account for, in the colored ring.
    ///
    /// Deliberately not one of the twelve category tints. It started as brand
    /// blue, which is also Housing — and a second blue arc on a ring where blue
    /// already means "Housing" reads as a bug, not as "other". It can't be any
    /// saturated color either: `fees` is gray and `other` is system gray, so a
    /// gray category and a gray remainder would collide the same way. A pale
    /// neutral can't be mistaken for a category at all, and it's clearly darker
    /// than `track`, so it still reads as spend rather than as empty ring.
    static let unattributed = Color.secondary.opacity(0.45)
}

/// `WidgetText` (in Shared) owns the number formatting, so the app can render
/// the same strings in tests and previews.
