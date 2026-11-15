import AppIntents
import WidgetKit

/// The small widget's cycle button.
///
/// A widget button can't ask the app to do anything — the app isn't running —
/// so the intent does the whole job itself: flip the shared preference and tell
/// WidgetKit to redraw. That is what makes it safe: it touches a display
/// preference and nothing else. No transaction data is read or written here, and
/// no amount of tapping can spend money or unlock the app.
struct CycleWidgetMetricIntent: AppIntent {
    static var title: LocalizedStringResource = "Show the Next Budget Figure"

    /// No parameters, no `openAppWhenRun`: the widget updates in place.
    static var isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        WidgetMetric.save(WidgetMetric.load().next)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
