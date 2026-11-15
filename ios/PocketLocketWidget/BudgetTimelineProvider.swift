import Foundation
import WidgetKit

/// What a widget draws at one moment.
struct BudgetEntry: TimelineEntry, Equatable {
    let date: Date
    /// `nil` when the app has never published anything — the "open PocketLocket"
    /// empty state, not a zero.
    let snapshot: WidgetSnapshot?
    let metric: WidgetMetric
    /// Whether this entry's ring is split into per-category colors.
    ///
    /// Resolved here rather than in the views, which are meant to draw and
    /// nothing else — and resolved once per timeline, so every widget in a
    /// refresh agrees on whether it is colored.
    let colorfulRing: Bool

    init(
        date: Date,
        snapshot: WidgetSnapshot?,
        metric: WidgetMetric,
        colorfulRing: Bool = false
    ) {
        self.date = date
        self.snapshot = snapshot
        self.metric = metric
        self.colorfulRing = colorfulRing
    }

    /// The readout is anchored to `date`, not to `Date()`, so the second entry
    /// in the timeline correctly flips to "as of …" at the moment it becomes
    /// stale without needing the app to run.
    var readout: WidgetReadout? {
        snapshot.map { WidgetReadout(snapshot: $0, metric: metric, now: date) }
    }

    /// Colored segments for this entry's ring, or `nil` for the plain one.
    ///
    /// Over budget the shares still describe the whole month's spend, so the
    /// segments describe the first lap and the red overflow lap is drawn on top.
    ///
    /// - Parameter limit: how many categories the ring may name. Each layout
    ///   passes the number of category rows it actually shows, so the ring never
    ///   carries a color the widget has no legend for.
    func ringSegments(limit: Int = WidgetRingSegments.displayedCategories) -> [WidgetRingSegment]? {
        guard colorfulRing, let snapshot, snapshot.hasBudget else { return nil }
        let segments = WidgetRingSegments.make(
            fraction: snapshot.fraction,
            categories: snapshot.categories,
            limit: limit
        )
        return segments.isEmpty ? nil : segments
    }
}

/// Hands WidgetKit the snapshot the app published.
///
/// Deliberately a plain `TimelineProvider` rather than a configurable one: the
/// metric is a single shared preference that the cycle button, the long-press
/// menu and Settings all write, so every widget on the Home Screen agrees. A
/// per-widget `@Parameter` would have given the same three options a fourth,
/// contradictory place to live.
struct BudgetTimelineProvider: TimelineProvider {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    // MARK: Placeholder

    /// Representative data, per Apple's guideline that a gallery preview should
    /// look like the widget in use rather than like an error.
    static let sampleSnapshot = WidgetSnapshot(
        schemaVersion: WidgetSnapshot.schemaVersion,
        monthStart: Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date(),
        totalSpent: 1860,
        monthlyBudget: 3000,
        categories: [
            WidgetCategory(category: .housing, amount: 1100, share: 0.59),
            WidgetCategory(category: .groceries, amount: 420, share: 0.23),
            WidgetCategory(category: .food, amount: 340, share: 0.18)
        ],
        fraction: 0.62,
        safeToSpend: 57,
        isoCurrencyCode: Locale.current.currency?.identifier ?? "USD",
        showsAmounts: false,
        updatedAt: Date()
    )

    func placeholder(in context: Context) -> BudgetEntry {
        previewEntry()
    }

    // MARK: Snapshot

    func getSnapshot(in context: Context, completion: @escaping (BudgetEntry) -> Void) {
        // The gallery and the configuration sheet show a populated widget rather
        // than the empty state, so a first-time user can see what they'd be
        // adding. Once there is real data, previews show that instead.
        if context.isPreview, WidgetSnapshot.load() == nil {
            completion(previewEntry())
        } else {
            completion(currentEntry())
        }
    }

    /// The gallery entry: representative data, with the ring in whatever style
    /// the user's preference currently says. In the gallery the shared suite is
    /// usually untouched, which is exactly the colourful default we want a
    /// first-time user to see.
    private func previewEntry() -> BudgetEntry {
        BudgetEntry(
            date: Date(),
            snapshot: Self.sampleSnapshot,
            metric: .percent,
            colorfulRing: WidgetPreferences.colorfulRing()
        )
    }

    // MARK: Timeline

    func getTimeline(in context: Context, completion: @escaping (Timeline<BudgetEntry>) -> Void) {
        completion(timeline(now: Date()))
    }

    /// Two entries: now, and the instant the snapshot goes stale.
    ///
    /// WidgetKit won't let a widget refresh itself on a schedule the app owns,
    /// and pretending otherwise means a widget that quietly shows last week's
    /// number forever. Instead, the widget promises to re-render exactly when
    /// its own honesty about the data changes, and relies on the app calling
    /// `reloadAllTimelines()` for everything in between.
    func timeline(now: Date) -> Timeline<BudgetEntry> {
        timeline(now: now, colorfulRing: WidgetPreferences.colorfulRing())
    }

    /// `colorfulRing` is a parameter rather than a read inside, so a test can
    /// pin both ring styles without reaching into shared defaults.
    func timeline(now: Date, colorfulRing: Bool) -> Timeline<BudgetEntry> {
        let snapshot = WidgetSnapshot.load()
        let metric = WidgetMetric.load()
        let entry = BudgetEntry(date: now, snapshot: snapshot, metric: metric, colorfulRing: colorfulRing)
        guard let snapshot else {
            return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(4 * 3600)))
        }

        // `isStale` is inclusive, but the age is truncated to whole minutes, so
        // an entry scheduled exactly on the threshold could land a fraction of a
        // second early and render one more minute of the fresh caption.
        let staleAt = snapshot.updatedAt
            .addingTimeInterval(TimeInterval(WidgetSnapshot.staleAfterMinutes * 60))
            .addingTimeInterval(1)
        let dates = [now, max(now.addingTimeInterval(900), staleAt)]
        // Both entries carry the same `colorfulRing`: the second one is only
        // there to relabel the data as stale, so it must not also restyle it.
        let entries = dates.map { BudgetEntry(date: $0, snapshot: snapshot, metric: metric, colorfulRing: colorfulRing) }
        // `.after` rather than `.atEnd`: the second entry is a label change, not
        // new data, so asking for a fresh timeline the moment it renders would
        // just spend reload budget on the same numbers.
        return Timeline(entries: entries, policy: .after(dates[1]))
    }

    private func currentEntry() -> BudgetEntry {
        BudgetEntry(
            date: Date(),
            snapshot: WidgetSnapshot.load(),
            metric: WidgetMetric.load(),
            colorfulRing: WidgetPreferences.colorfulRing()
        )
    }
}
