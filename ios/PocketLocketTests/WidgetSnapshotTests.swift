import XCTest
@testable import PocketLocket

/// Covers the snapshot the widgets draw from: the arithmetic, the privacy
/// guarantee, and the round-trip through the App Group.
final class WidgetSnapshotTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private let monthStart = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z
    private let now = Date(timeIntervalSince1970: 1_767_484_800)        // 2026-01-04

    private func item(_ category: SpendCategory, _ amount: Double) -> SpendItem {
        SpendItem(category: category, amount: amount)
    }

    private func makeDefaults() -> UserDefaults {
        // A named suite we can wipe, rather than touching the real App Group.
        let suite = "WidgetSnapshotTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    // MARK: - Building

    func testBuildComputesFractionAndShares() {
        let snapshot = WidgetSnapshot.build(
            items: [item(.housing, 1_000), item(.food, 500)],
            monthlyBudget: 3_000,
            monthStart: monthStart,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.totalSpent, 1_500, accuracy: 0.001)
        XCTAssertEqual(snapshot.fraction ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.categories.count, 2)
        // Largest first, shares summing to the whole.
        XCTAssertEqual(snapshot.categories.first?.category, .housing)
        XCTAssertEqual(snapshot.categories.reduce(0) { $0 + $1.share }, 1, accuracy: 0.0001)
    }

    func testBuildWithoutBudgetLeavesFractionNil() {
        let snapshot = WidgetSnapshot.build(
            items: [item(.food, 40)],
            monthlyBudget: 0,
            monthStart: monthStart,
            now: now,
            calendar: calendar
        )
        XCTAssertNil(snapshot.fraction)
        XCTAssertFalse(snapshot.hasBudget)
        // Still reports what went out, so the widget has something to draw.
        XCTAssertEqual(snapshot.totalSpent, 40, accuracy: 0.001)
    }

    func testBuildExcludesIncomeAndTransfers() {
        let snapshot = WidgetSnapshot.build(
            items: [item(.food, 100), item(.income, 900), item(.transfer, 500)],
            monthlyBudget: 1_000,
            monthStart: monthStart,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(snapshot.totalSpent, 100, accuracy: 0.001)
        XCTAssertEqual(snapshot.categories.map(\.category), [.food])
    }

    func testBuildCapsCategoryCount() {
        let many = (0..<12).map { SpendItem(category: [.food, .groceries, .shopping, .housing, .transport, .travel, .entertainment, .health, .services, .fees, .other, .food][($0 + 1) % 12], amount: Double(12 - $0)) }
        let snapshot = WidgetSnapshot.build(
            items: many,
            monthlyBudget: 1_000,
            monthStart: monthStart,
            now: now,
            calendar: calendar
        )
        XCTAssertLessThanOrEqual(snapshot.categories.count, 6)
    }

    // MARK: - Privacy

    /// The point of the whole percent-first design: with amounts hidden the
    /// dollars are not in the file, not merely unrendered.
    func testAmountsAreAbsentFromEncodingWhenHidden() throws {
        let snapshot = WidgetSnapshot.build(
            items: [item(.food, 250.5), item(.groceries, 100)],
            monthlyBudget: 1_000,
            monthStart: monthStart,
            now: now,
            calendar: calendar,
            showsAmounts: false
        )
        XCTAssertTrue(snapshot.categories.allSatisfy { $0.amount == nil })

        let data = try XCTUnwrap(snapshot.encoded())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let categories = try XCTUnwrap(json["categories"] as? [[String: Any]])
        for row in categories {
            XCTAssertNil(row["amount"], "amount key must not be written when amounts are off")
        }
        XCTAssertEqual(json["showsAmounts"] as? Bool, false)
    }

    func testAmountsArePresentWhenEnabled() throws {
        let snapshot = WidgetSnapshot.build(
            items: [item(.food, 250.5)],
            monthlyBudget: 1_000,
            monthStart: monthStart,
            now: now,
            calendar: calendar,
            showsAmounts: true
        )
        let data = try XCTUnwrap(snapshot.encoded())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let categories = try XCTUnwrap(json["categories"] as? [[String: Any]])
        XCTAssertEqual(try XCTUnwrap(categories.first?["amount"] as? Double), 250.5, accuracy: 0.001)
    }

    // MARK: - Round trip

    func testEncodeDecodeRoundTrip() throws {
        let snapshot = WidgetSnapshot.build(
            items: [item(.housing, 800), item(.food, 200)],
            monthlyBudget: 1_200,
            monthStart: monthStart,
            now: now,
            calendar: calendar,
            isoCurrencyCode: "EUR",
            showsAmounts: true
        )
        let data = try XCTUnwrap(snapshot.encoded())
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testLoadIgnoresFutureSchema() {
        let defaults = makeDefaults()
        let future = WidgetSnapshot(
            schemaVersion: WidgetSnapshot.schemaVersion + 1,
            monthStart: monthStart,
            totalSpent: 10,
            monthlyBudget: 20,
            categories: [],
            fraction: 0.5,
            safeToSpend: nil,
            isoCurrencyCode: "USD",
            showsAmounts: false,
            updatedAt: now
        )
        defaults.set(try? future.encoded(), forKey: WidgetSnapshotStore.key)
        XCTAssertNil(WidgetSnapshot.load(from: defaults))
    }

    func testLoadIgnoresGarbage() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: WidgetSnapshotStore.key)
        XCTAssertNil(WidgetSnapshot.load(from: defaults))
    }

    func testLoadReturnsNilWhenNothingPublished() {
        XCTAssertNil(WidgetSnapshot.load(from: makeDefaults()))
    }

    // MARK: - Staleness

    func testStaleness() {
        let snapshot = WidgetSnapshot(
            schemaVersion: WidgetSnapshot.schemaVersion,
            monthStart: monthStart,
            totalSpent: 1,
            monthlyBudget: 2,
            categories: [],
            fraction: 0.5,
            safeToSpend: nil,
            isoCurrencyCode: "USD",
            showsAmounts: false,
            updatedAt: now
        )
        XCTAssertFalse(snapshot.isStale(now: now.addingTimeInterval(60 * TimeInterval(WidgetSnapshot.staleAfterMinutes - 1))))
        XCTAssertTrue(snapshot.isStale(now: now.addingTimeInterval(60 * TimeInterval(WidgetSnapshot.staleAfterMinutes + 1))))
        XCTAssertEqual(snapshot.ageInMinutes(now: now.addingTimeInterval(60 * 42)), 42)
    }

    func testAgeStrings() {
        let snapshot = WidgetSnapshot(
            schemaVersion: WidgetSnapshot.schemaVersion,
            monthStart: monthStart,
            totalSpent: 1,
            monthlyBudget: 2,
            categories: [],
            fraction: 0.5,
            safeToSpend: nil,
            isoCurrencyCode: "USD",
            showsAmounts: false,
            updatedAt: now
        )
        XCTAssertEqual(WidgetText.age(snapshot, now: now), "Just now")
        XCTAssertEqual(WidgetText.age(snapshot, now: now.addingTimeInterval(60 * 12)), "12m ago")
        XCTAssertEqual(WidgetText.age(snapshot, now: now.addingTimeInterval(60 * 60 * 3)), "3h ago")
        XCTAssertEqual(WidgetText.age(snapshot, now: now.addingTimeInterval(60 * 60 * 30)), "Yesterday")
        XCTAssertEqual(WidgetText.age(snapshot, now: now.addingTimeInterval(60 * 60 * 72)), "3d ago")
    }

    // MARK: - Over budget

    func testOverBudgetReporting() {
        let snapshot = WidgetSnapshot.build(
            items: [item(.food, 4_000)],
            monthlyBudget: 3_000,
            monthStart: monthStart,
            now: now,
            calendar: calendar
        )
        XCTAssertTrue(snapshot.isOverBudget)
        // Negative, mirroring HomeViewModel.remaining.
        XCTAssertEqual(snapshot.remaining, -1_000, accuracy: 0.001)
        // Unclamped, so the view can draw a second lap.
        XCTAssertEqual(snapshot.fraction ?? 0, 1.333, accuracy: 0.01)
    }
}
