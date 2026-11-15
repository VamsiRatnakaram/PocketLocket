import XCTest
import SwiftUI
import WidgetKit
@testable import PocketLocketWidgetTests

/// Renders every widget layout to PNGs and pins down what each one is allowed
/// to say.
///
/// The Face ID gate means we can't screenshot a live widget on a simulator
/// headlessly, so these render the same views directly. `\.widgetFamily` is
/// read-only, which is why `BudgetWidgetEntryView` takes the family as a
/// parameter instead of only reading the environment.
final class WidgetLayoutTests: XCTestCase {

    private var outputDir: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        outputDir = "/tmp/widget_layouts"
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        print("Widget renders -> \(outputDir!)")
    }

    // MARK: - Sample data

    /// A month where Housing dominates and four smaller categories follow,
    /// which is the shape the layouts were designed around.
    private func sampleSnapshot(showsAmounts: Bool, now: Date = Date()) -> WidgetSnapshot {
        let calendar = Calendar(identifier: .gregorian)
        let monthStart = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        var items: [SpendItem] = Array(repeating: SpendItem(category: .housing, amount: 250), count: 5)
        items += [
            SpendItem(category: .groceries, amount: 210),
            SpendItem(category: .food, amount: 180),
            SpendItem(category: .transport, amount: 90),
            SpendItem(category: .entertainment, amount: 60),
        ]
        return WidgetSnapshot.build(
            items: items,
            monthlyBudget: 2400,
            monthStart: monthStart,
            now: now,
            calendar: calendar,
            categoryBudgets: [:],
            safeToSpendFocus: [],
            isoCurrencyCode: "USD",
            showsAmounts: showsAmounts,
            maxCategories: 4
        )
    }

    // MARK: - Renders

    /// One method per size: `ImageRenderer` intermittently fails to encode when
    /// asked for many images in a single test, which would otherwise report as a
    /// layout failure.
    @MainActor
    func testRenderSmall() throws {
        renderFamily(.systemSmall)
    }

    @MainActor
    func testRenderMedium() throws {
        renderFamily(.systemMedium)
    }

    @MainActor
    func testRenderLarge() throws {
        renderFamily(.systemLarge)
    }

    @MainActor
    func testRenderLockScreenCircular() throws {
        renderFamily(.accessoryCircular)
    }

    @MainActor
    func testRenderLockScreenRectangular() throws {
        renderFamily(.accessoryRectangular)
    }

    @MainActor
    private func renderFamily(_ family: WidgetFamily) {
        let entry = BudgetEntry(date: Date(), snapshot: sampleSnapshot(showsAmounts: false), metric: .percent)
        render(BudgetWidgetEntryView(entry: entry, family: family),
               size: family.testSize,
               name: "budget_\(slug(family))")
    }

    @MainActor
    func testRenderPercentMetricOnSmall() throws {
        renderMetric(.percent)
    }

    @MainActor
    func testRenderRemainingMetricOnSmall() throws {
        renderMetric(.remaining)
    }

    @MainActor
    func testRenderSafeToSpendMetricOnSmall() throws {
        renderMetric(.safeToSpend)
    }

    @MainActor
    private func renderMetric(_ metric: WidgetMetric) {
        let entry = BudgetEntry(date: Date(), snapshot: sampleSnapshot(showsAmounts: false), metric: metric)
        render(BudgetWidgetEntryView(entry: entry, family: .systemSmall),
               size: CGSize(width: 160, height: 160),
               name: "budget_small_\(metric.rawValue)")
    }

    /// The medium layout with dollar amounts turned on.
    @MainActor
    func testRenderMediumWithAmounts() throws {
        let snapshot = sampleSnapshot(showsAmounts: true)
        let entry = BudgetEntry(date: Date(), snapshot: snapshot, metric: .safeToSpend)
        render(BudgetWidgetEntryView(entry: entry, family: .systemMedium),
               size: CGSize(width: 345, height: 160),
               name: "budget_medium_safe_to_spend_usd")
    }

    // MARK: - Colored ring

    /// The colored ring is the default look, so it needs its own renders: a
    /// regression that silently collapses it back to one flat arc would leave
    /// every other assertion in this file green.
    @MainActor
    func testRenderSmallColorfulRing() throws {
        renderColorful(.systemSmall)
    }

    @MainActor
    func testRenderMediumColorfulRing() throws {
        renderColorful(.systemMedium)
    }

    @MainActor
    func testRenderLargeColorfulRing() throws {
        renderColorful(.systemLarge)
    }

    @MainActor
    private func renderColorful(_ family: WidgetFamily) {
        let entry = BudgetEntry(
            date: Date(),
            snapshot: sampleSnapshot(showsAmounts: false),
            metric: .percent,
            colorfulRing: true
        )
        XCTAssertNotNil(entry.ringSegments(), "the sample month has a budget and categories")
        render(BudgetWidgetEntryView(entry: entry, family: family),
               size: family.testSize,
               name: "budget_\(slug(family))_colorful")
    }

    /// Over budget *and* colored: the categories keep their colors and the
    /// second lap goes red on top, rather than the whole ring turning amber.
    @MainActor
    func testRenderColorfulRingOverBudget() throws {
        let calendar = Calendar(identifier: .gregorian)
        let monthStart = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let snapshot = WidgetSnapshot.build(
            items: [
                SpendItem(category: .housing, amount: 1200),
                SpendItem(category: .groceries, amount: 700),
                SpendItem(category: .food, amount: 500),
                SpendItem(category: .transport, amount: 350),
            ],
            monthlyBudget: 2000,
            monthStart: monthStart,
            now: Date(),
            calendar: calendar,
            isoCurrencyCode: "USD"
        )
        let entry = BudgetEntry(date: Date(), snapshot: snapshot, metric: .percent, colorfulRing: true)
        XCTAssertGreaterThan(snapshot.fraction ?? 0, 1, "sample must actually be over budget")
        render(BudgetWidgetEntryView(entry: entry, family: .systemSmall),
               size: CGSize(width: 160, height: 160),
               name: "budget_small_colorful_over_budget")
    }

    /// The plain ring must still be reachable — it's a user setting, not dead
    /// code, and it's what accented/vibrant rendering modes get anyway.
    func testPlainEntryHasNoSegments() {
        let entry = BudgetEntry(date: Date(), snapshot: sampleSnapshot(showsAmounts: false), metric: .percent)
        XCTAssertNil(entry.ringSegments())
    }

    /// No budget means no arc to color, colored or not.
    func testColorfulEntryWithoutABudgetHasNoSegments() {
        let calendar = Calendar(identifier: .gregorian)
        let monthStart = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let snapshot = WidgetSnapshot.build(
            items: [SpendItem(category: .food, amount: 40)],
            monthlyBudget: 0,
            monthStart: monthStart,
            now: Date(),
            calendar: calendar
        )
        let entry = BudgetEntry(date: Date(), snapshot: snapshot, metric: .percent, colorfulRing: true)
        XCTAssertNil(entry.ringSegments())
    }

    /// The medium widget shows three rows, so its ring may name at most three
    /// categories; anything more would be an unexplained color.
    func testMediumRingNamesNoMoreCategoriesThanTheLayoutLists() {
        let calendar = Calendar(identifier: .gregorian)
        let monthStart = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let snapshot = WidgetSnapshot.build(
            items: [
                SpendItem(category: .housing, amount: 800),
                SpendItem(category: .groceries, amount: 400),
                SpendItem(category: .food, amount: 300),
                SpendItem(category: .transport, amount: 200),
                SpendItem(category: .entertainment, amount: 90),
            ],
            monthlyBudget: 3000,
            monthStart: monthStart,
            now: Date(),
            calendar: calendar,
            maxCategories: 6
        )
        XCTAssertEqual(snapshot.categories.count, 5, "sample carries more rows than medium lists")
        let entry = BudgetEntry(date: Date(), snapshot: snapshot, metric: .percent, colorfulRing: true)
        let named = (entry.ringSegments() ?? []).filter { $0.category != nil }
        XCTAssertEqual(named.count, WidgetRingSegments.displayedCategories)
    }

    // MARK: - Preference

    /// An untouched suite must read as the *colorful* ring. The key is stored
    /// inverted precisely for this, so it's worth pinning.
    func testColorfulRingIsTheDefaultForAnUntouchedStore() {
        let name = "com.vratnakaram.PocketLocketTests.ringpref"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        defer { suite.removePersistentDomain(forName: name) }

        XCTAssertTrue(WidgetPreferences.colorfulRing(from: suite))

        WidgetPreferences.setColorfulRing(false, defaults: suite)
        XCTAssertFalse(WidgetPreferences.colorfulRing(from: suite))
        XCTAssertTrue(suite.bool(forKey: WidgetPreferences.monochromeRingKey),
                      "stored inverted so an unwritten key means colorful")

        WidgetPreferences.setColorfulRing(true, defaults: suite)
        XCTAssertTrue(WidgetPreferences.colorfulRing(from: suite))
    }

    /// What a brand-new install sees before the app has published anything.
    @MainActor
    func testRenderEmptyState() throws {
        let entry = BudgetEntry(date: Date(), snapshot: nil, metric: .percent)
        render(BudgetWidgetEntryView(entry: entry, family: .systemSmall),
               size: CGSize(width: 160, height: 160),
               name: "budget_small_empty")
    }

    /// Over budget has to look different, not just read differently.
    @MainActor
    func testRenderOverBudget() throws {
        let calendar = Calendar(identifier: .gregorian)
        let monthStart = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let snapshot = WidgetSnapshot.build(
            items: Array(repeating: SpendItem(category: .shopping, amount: 1000), count: 4),
            monthlyBudget: 2400,
            monthStart: monthStart,
            now: Date(),
            calendar: calendar,
            isoCurrencyCode: "USD"
        )
        let entry = BudgetEntry(date: Date(), snapshot: snapshot, metric: .percent)
        render(BudgetWidgetEntryView(entry: entry, family: .systemSmall),
               size: CGSize(width: 160, height: 160),
               name: "budget_small_over_budget")
    }

    // MARK: - Readout

    /// A stale snapshot must swap the caption for "as of …" — a widget can't
    /// recompute anything, so it has to be honest about its age.
    func testStaleSnapshotChangesTheCaption() {
        let old = sampleSnapshot(showsAmounts: false,
                                 now: Date().addingTimeInterval(-TimeInterval(WidgetSnapshot.staleAfterMinutes + 60) * 60))
        XCTAssertTrue(old.isStale())
        let readout = WidgetReadout(snapshot: old, metric: .percent)
        XCTAssertTrue(readout.caption.localizedCaseInsensitiveContains("as of"),
                      "expected an 'as of' caption, got \(readout.caption)")
    }

    func testFreshSnapshotCaptionDoesNotClaimStaleness() {
        let snapshot = sampleSnapshot(showsAmounts: false)
        XCTAssertFalse(snapshot.isStale())
        let readout = WidgetReadout(snapshot: snapshot, metric: .percent)
        XCTAssertFalse(readout.caption.localizedCaseInsensitiveContains("as of"))
    }

    /// Percent of a $2,400 budget with $1,790 spent is 75%.
    func testPercentHeadlineMatchesTheRatio() {
        let snapshot = sampleSnapshot(showsAmounts: false)
        let readout = WidgetReadout(snapshot: snapshot, metric: .percent)
        XCTAssertEqual(readout.headline, WidgetText.percent(snapshot.fraction ?? 0))
        XCTAssertEqual(snapshot.totalSpent, 1790, accuracy: 0.001)
    }

    func testRemainingHeadlineDropsTheSignWhenOverBudget() {
        let calendar = Calendar(identifier: .gregorian)
        let monthStart = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let over = WidgetSnapshot.build(
            items: [SpendItem(category: .shopping, amount: 3000)],
            monthlyBudget: 2400,
            monthStart: monthStart,
            now: Date(),
            calendar: calendar
        )
        let readout = WidgetReadout(snapshot: over, metric: .remaining)
        XCTAssertTrue(over.isOverBudget)
        XCTAssertEqual(readout.caption, "over budget")
        XCTAssertFalse(readout.headline.contains("-"))
    }

    /// No budget set is its own empty state, distinct from "you spent nothing".
    func testNoBudgetReadout() {
        let calendar = Calendar(identifier: .gregorian)
        let monthStart = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let snapshot = WidgetSnapshot.build(
            items: [SpendItem(category: .food, amount: 40)],
            monthlyBudget: 0,
            monthStart: monthStart,
            now: Date(),
            calendar: calendar
        )
        let readout = WidgetReadout(snapshot: snapshot, metric: .safeToSpend)
        XCTAssertEqual(readout.headline, "—")
        XCTAssertTrue(readout.caption.localizedCaseInsensitiveContains("budget"))
    }

    // MARK: - Privacy and ordering

    /// Amounts hidden means the dollars are genuinely absent, not merely
    /// unrendered.
    func testHiddenAmountsAreAbsentFromThePayload() throws {
        let hidden = sampleSnapshot(showsAmounts: false)
        XCTAssertTrue(hidden.categories.allSatisfy { $0.amount == nil })
        let data = try XCTUnwrap(hidden.encoded())
        XCTAssertFalse(String(data: data, encoding: .utf8)!.contains("\"amount\""))

        let shown = sampleSnapshot(showsAmounts: true)
        XCTAssertTrue(shown.categories.allSatisfy { $0.amount != nil })
    }

    /// The largest category leads, and the cap is respected.
    func testCategoriesAreOrderedBySpendAndTrimmed() {
        let snapshot = sampleSnapshot(showsAmounts: false)
        XCTAssertEqual(snapshot.categories.count, 4)
        XCTAssertEqual(snapshot.categories.first?.category, .housing)
        let shares = snapshot.categories.map(\.share)
        XCTAssertEqual(shares, shares.sorted(by: >))
    }

    // MARK: - Timeline

    /// The provider must hand over a second entry at the moment the snapshot
    /// goes stale, so the "as of" label appears without the app running.
    func testTimelineAddsTheStaleFlipEntry() throws {
        // Published four hours ago: still fresh right now, and the timeline's
        // second entry lands at the minute it crosses the stale threshold.
        let publishedAt = Date().addingTimeInterval(-TimeInterval(WidgetSnapshot.staleAfterMinutes - 60) * 60)
        let snapshot = sampleSnapshot(showsAmounts: false, now: publishedAt)
        let data = try XCTUnwrap(snapshot.encoded())
        AppGroup.defaults.set(data, forKey: WidgetSnapshotStore.key)
        defer { WidgetSnapshotStore.clear(reload: false) }

        let timeline = BudgetTimelineProvider().timeline(now: Date())
        XCTAssertEqual(timeline.entries.count, 2)
        XCTAssertFalse(timeline.entries[0].readout?.caption.contains("as of") ?? true)
        XCTAssertTrue(timeline.entries[1].readout?.caption.contains("as of") ?? false)
    }

    /// Nothing published yet still has to produce a usable timeline.
    func testTimelineWithoutAnyData() {
        WidgetSnapshotStore.clear(reload: false)
        let timeline = BudgetTimelineProvider().timeline(now: Date())
        XCTAssertEqual(timeline.entries.count, 1)
        XCTAssertNil(timeline.entries[0].snapshot)
    }

    // MARK: - Helpers

    private func slug(_ family: WidgetFamily) -> String {
        switch family {
        case .systemSmall: return "small"
        case .systemMedium: return "medium"
        case .systemLarge: return "large"
        case .accessoryCircular: return "circular"
        case .accessoryRectangular: return "rectangular"
        default: return "other"
        }
    }

    @MainActor
    private func render<V: View>(_ view: V, size: CGSize, name: String) {
        // `containerBackground(for: .widget)` only draws inside a real widget
        // host, so ImageRenderer sees a zero-size view there. The ZStack gives
        // the render a canvas; the widget's own background is what it replaces.
        let content = ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.systemBackground))
            view
        }
        .frame(width: size.width, height: size.height)
        .padding(8)
        .background(Color(.secondarySystemBackground))

        // `ImageRenderer` intermittently fails to encode — `zlib error` /
        // "No IDATs written into file" — with nothing wrong in the view, and
        // more often once a process has produced many images. Retrying is the
        // only mitigation available; a layout that genuinely can't draw would
        // fail all three attempts.
        for attempt in 1...3 {
            let renderer = ImageRenderer(content: content)
            renderer.scale = 3
            if let ui = renderer.uiImage, let data = ui.pngData(), data.count > 8 {
                let url = URL(fileURLWithPath: outputDir).appendingPathComponent("\(name).png")
                try? data.write(to: url)
                print("✓ \(url.lastPathComponent) (\(Int(size.width))x\(Int(size.height)))\(attempt > 1 ? " [attempt \(attempt)]" : "")")
                return
            }
        }
        XCTFail("Failed to render \(name) after 3 attempts")
    }
}

private extension WidgetFamily {
    /// Apple doesn't expose widget sizes, so these are the standard points for
    /// the sizes we declare.
    var testSize: CGSize {
        switch self {
        case .systemSmall: return CGSize(width: 160, height: 160)
        case .systemMedium: return CGSize(width: 345, height: 160)
        case .systemLarge: return CGSize(width: 345, height: 360)
        case .accessoryCircular: return CGSize(width: 100, height: 100)
        case .accessoryRectangular: return CGSize(width: 300, height: 100)
        default: return CGSize(width: 160, height: 160)
        }
    }
}
