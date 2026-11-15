import SwiftUI
import WidgetKit

/// PocketLocket's widgets.
///
/// One `BudgetEntry`, five presentations: three Home Screen sizes and two Lock
/// Screen shapes, all drawn from the same snapshot the app publishes. `widgetURL`
/// sends every tap to the Home tab — never straight to data, because the app
/// still unlocks with Face ID first.
@main
struct PocketLocketWidgetBundle: WidgetBundle {
    var body: some Widget {
        BudgetWidgets()
    }
}

struct BudgetWidgets: Widget {
    /// Stable across releases: renaming this orphans every widget already placed.
    static let kind = "PocketLocketBudgetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: BudgetTimelineProvider()) { entry in
            BudgetWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Budget")
        .description("How much of this month's budget you've used, and where it went.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

// No `.defaultView` preview: this SDK has no such modifier, and the gallery
// already gets representative data from the provider's `getSnapshot`, which is
// the documented way to control what a first-time user sees.
