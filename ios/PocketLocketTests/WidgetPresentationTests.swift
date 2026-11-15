import XCTest
@testable import PocketLocket

/// The widget's readout wording, the metric cycle, and the deep-link format —
/// all pure, all shared with the extension, so a wording or format regression
/// fails here rather than on a Home Screen.
final class WidgetPresentationTests: XCTestCase {
    private let monthStart = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z
    private let now = Date(timeIntervalSince1970: 1_767_484_800)        // 2026-01-04

    private func snapshot(
        totalSpent: Double,
        budget: Double,
        safeToSpend: Double? = nil,
        showsAmounts: Bool = false,
        code: String = "USD"
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            schemaVersion: WidgetSnapshot.schemaVersion,
            monthStart: monthStart,
            totalSpent: totalSpent,
            monthlyBudget: budget,
            categories: [],
            fraction: budget > 0 ? totalSpent / budget : nil,
            safeToSpend: safeToSpend,
            isoCurrencyCode: code,
            showsAmounts: showsAmounts,
            updatedAt: now
        )
    }

    // MARK: - Readout

    func testPercentReadout() {
        let readout = WidgetReadout(
            snapshot: snapshot(totalSpent: 1_860, budget: 3_000),
            metric: .percent,
            now: now
        )
        XCTAssertEqual(readout.headline, "62%")
        XCTAssertTrue(readout.caption.contains("budget"))
        XCTAssertFalse(readout.isOver)
    }

    func testRemainingReadoutUnderBudget() {
        let readout = WidgetReadout(
            snapshot: snapshot(totalSpent: 1_000, budget: 3_000),
            metric: .remaining,
            now: now
        )
        XCTAssertEqual(readout.headline, "$2,000")
        XCTAssertEqual(readout.caption, "left")
    }

    func testRemainingReadoutOverBudget() {
        let base = snapshot(totalSpent: 4_000, budget: 3_000)
        let readout = WidgetReadout(snapshot: base, metric: .remaining, now: now)
        // Absolute value with the caption carrying the sign — a bare "-$1,000"
        // next to "left" would read as a contradiction.
        XCTAssertEqual(readout.headline, "$1,000")
        XCTAssertEqual(readout.caption, "over budget")
        XCTAssertTrue(readout.isOver)
    }

    func testRemainingReadoutWithoutBudgetShowsSpend() {
        let readout = WidgetReadout(
            snapshot: snapshot(totalSpent: 512, budget: 0),
            metric: .remaining,
            now: now
        )
        XCTAssertEqual(readout.headline, "$512")
        XCTAssertEqual(readout.caption, "spent, no budget set")
        XCTAssertFalse(readout.hasBudget)
    }

    func testSafeToSpendReadout() {
        let readout = WidgetReadout(
            snapshot: snapshot(totalSpent: 1_000, budget: 3_000, safeToSpend: 57.4),
            metric: .safeToSpend,
            now: now
        )
        XCTAssertEqual(readout.headline, "$57")
        XCTAssertEqual(readout.caption, "a day left")
    }

    func testSafeToSpendWithoutBudget() {
        let readout = WidgetReadout(
            snapshot: snapshot(totalSpent: 100, budget: 0),
            metric: .safeToSpend,
            now: now
        )
        XCTAssertEqual(readout.headline, "—")
        XCTAssertEqual(readout.caption, "set a budget to see this")
    }

    /// When the app hasn't run in hours the caption admits it, rather than
    /// presenting an old number as today's.
    func testStaleSnapshotReplacesCaption() {
        let readout = WidgetReadout(
            snapshot: snapshot(totalSpent: 1_860, budget: 3_000),
            metric: .percent,
            now: now.addingTimeInterval(60 * 60 * 20)
        )
        XCTAssertTrue(readout.caption.hasPrefix("as of "))
        XCTAssertTrue(readout.caption.contains("20h ago"))
    }

    func testCurrencyCodeIsHonoured() {
        let readout = WidgetReadout(
            snapshot: snapshot(totalSpent: 0, budget: 3_000, code: "EUR"),
            metric: .remaining,
            now: now
        )
        XCTAssertTrue(readout.headline.contains("€"), readout.headline)
    }

    // MARK: - Metric

    func testMetricCycleWraps() {
        XCTAssertEqual(WidgetMetric.percent.next, .remaining)
        XCTAssertEqual(WidgetMetric.remaining.next, .safeToSpend)
        XCTAssertEqual(WidgetMetric.safeToSpend.next, .percent)
    }

    func testMetricPersistsThroughTheSuite() {
        let suite = "WidgetPresentationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // Unset means percent, so a widget added before the app wrote anything
        // still shows the default rather than nonsense.
        XCTAssertEqual(WidgetMetric.load(from: defaults), .percent)
        WidgetMetric.save(.safeToSpend, to: defaults)
        XCTAssertEqual(WidgetMetric.load(from: defaults), .safeToSpend)
    }

    func testMetricRawValuesAreStable() {
        // Renaming a raw value orphans a stored preference.
        XCTAssertEqual(WidgetMetric.allCases.map(\.rawValue), ["percent", "remaining", "safeToSpend"])
    }

    // MARK: - Deep links

    func testHomeLinkRoundTrip() throws {
        let url = WidgetDeepLink.home()
        XCTAssertEqual(WidgetDeepLink.destination(from: url), .home)
        XCTAssertNil(WidgetDeepLink.category(from: url))
    }

    func testCategoryLinkRoundTrip() throws {
        let url = try XCTUnwrap(WidgetDeepLink.category(.entertainment))
        XCTAssertEqual(WidgetDeepLink.destination(from: url), nil)
        XCTAssertEqual(WidgetDeepLink.category(from: url), .entertainment)
    }

    func testCategoryLinkForEveryCategory() {
        // A category that can't build a URL would silently drop its row's tap.
        for category in SpendCategory.allCases {
            XCTAssertNotNil(WidgetDeepLink.category(category), category.rawValue)
        }
    }

    func testForeignURLsAreIgnored() {
        XCTAssertNil(WidgetDeepLink.destination(from: URL(string: "https://example.com/home")!))
        XCTAssertNil(WidgetDeepLink.destination(from: URL(string: "pocketlocket://other/home")!))
        XCTAssertNil(WidgetDeepLink.destination(from: URL(string: "pocketlocket://widget/nonsense")!))
        XCTAssertNil(WidgetDeepLink.category(from: URL(string: "pocketlocket://category?id=food")!))
    }

    // MARK: - Preferences

    func testShowsAmountsDefaultsToOff() {
        let suite = "WidgetPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(WidgetPreferences.showsAmounts(from: defaults))
        WidgetPreferences.setShowsAmounts(true, defaults: defaults)
        XCTAssertTrue(WidgetPreferences.showsAmounts(from: defaults))
    }

    // MARK: - Publish / dedupe

    func testPublishSkipsReloadWhenVisibleContentUnchanged() {
        let suite = "WidgetPublishTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = WidgetSnapshot.build(
            items: [SpendItem(category: .food, amount: 120)],
            monthlyBudget: 1_000,
            monthStart: monthStart,
            now: now,
            calendar: Calendar(identifier: .gregorian)
        )
        XCTAssertTrue(WidgetSnapshotStore.publish(first, to: defaults, reload: false))

        // Same numbers, later timestamp: nothing a user could see has changed, so
        // no write and no reload budget spent.
        let later = WidgetSnapshot.build(
            items: [SpendItem(category: .food, amount: 120)],
            monthlyBudget: 1_000,
            monthStart: monthStart,
            now: now.addingTimeInterval(600),
            calendar: Calendar(identifier: .gregorian)
        )
        XCTAssertFalse(WidgetSnapshotStore.publish(later, to: defaults, reload: false))
        XCTAssertEqual(WidgetSnapshot.load(from: defaults)?.updatedAt, first.updatedAt)

        // Real spend does get through.
        let changed = WidgetSnapshot.build(
            items: [SpendItem(category: .food, amount: 121)],
            monthlyBudget: 1_000,
            monthStart: monthStart,
            now: now.addingTimeInterval(900),
            calendar: Calendar(identifier: .gregorian)
        )
        XCTAssertTrue(WidgetSnapshotStore.publish(changed, to: defaults, reload: false))
        let published = try? XCTUnwrap(WidgetSnapshot.load(from: defaults))
        XCTAssertEqual(published?.totalSpent ?? -1, 121, accuracy: 0.001)
    }

    func testClearRemovesSnapshot() {
        let suite = "WidgetClearTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let snapshot = WidgetSnapshot.build(
            items: [SpendItem(category: .food, amount: 120)],
            monthlyBudget: 1_000,
            monthStart: monthStart,
            now: now,
            calendar: Calendar(identifier: .gregorian)
        )
        WidgetSnapshotStore.publish(snapshot, to: defaults, reload: false)
        XCTAssertNotNil(WidgetSnapshot.load(from: defaults))

        WidgetSnapshotStore.clear(defaults: defaults)
        XCTAssertNil(WidgetSnapshot.load(from: defaults))
    }

    // MARK: - Pace

    func testDaysLeftCountsToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let day31 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        XCTAssertEqual(MonthlyPace.daysLeftInMonth(for: day1, calendar: calendar), 31)
        // Never zero, so the last day divides by 1 rather than crashing.
        XCTAssertEqual(MonthlyPace.daysLeftInMonth(for: day31, calendar: calendar), 1)
    }

    func testSafeToSpendBasisPrefersStarredBudgetedCategories() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let items = [
            SpendItem(category: .food, amount: 100),
            SpendItem(category: .groceries, amount: 50),
            SpendItem(category: .shopping, amount: 700)
        ]
        let basis = try XCTUnwrap(SafeToSpendBasis.resolve(
            items: items,
            monthlyBudget: 3_000,
            categoryBudgets: [.food: 400, .groceries: 300],
            focus: [.food, .groceries],
            calendar: calendar,
            now: monthStart
        ))
        XCTAssertEqual(basis.budget, 700, accuracy: 0.001)
        // Shopping is unstarred, so its 700 doesn't count against the basis.
        XCTAssertEqual(basis.spent, 150, accuracy: 0.001)
    }

    /// Starring a category you never set a limit for must not redefine the
    /// figure to "unlimited minus spend".
    func testStarredCategoryWithoutLimitFallsBackToOverallBudget() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let basis = SafeToSpendBasis.resolve(
            items: [SpendItem(category: .food, amount: 100)],
            monthlyBudget: 3_000,
            categoryBudgets: [:],
            focus: [.food],
            calendar: calendar,
            now: monthStart
        )
        XCTAssertEqual(basis?.budget ?? -1, 3_000, accuracy: 0.001)
        XCTAssertEqual(basis?.spent ?? -1, 100, accuracy: 0.001)
    }

    func testDailyAllowanceNeverNegative() {
        let basis = SafeToSpendBasis(budget: 100, spent: 500, label: "")
        XCTAssertEqual(basis.dailyAllowance(daysLeft: 10), 0)
    }
}
