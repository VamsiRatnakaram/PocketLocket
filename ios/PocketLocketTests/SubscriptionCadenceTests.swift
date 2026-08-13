import XCTest
@testable import PocketLocket

final class SubscriptionCadenceTests: XCTestCase {
    private let day: TimeInterval = 86_400

    private func date(daysAgo: Double, from now: Date) -> Date {
        now.addingTimeInterval(-daysAgo * day)
    }

    func testThreeMonthlyChargesClassifyAsMonthly() {
        let now = Date()
        let dates = [90, 60, 30, 0].map { date(daysAgo: Double($0), from: now) }
        let result = SubscriptionsView.Sub.classify(dates: dates, amount: 9.99, dataHorizonDays: 400, now: now)
        XCTAssertEqual(result.cadence, .monthly)
        XCTAssertEqual(result.confidence, .confirmed)
        XCTAssertEqual(result.monthlyEquivalent, 9.99, accuracy: 0.01)
    }

    func testTwoChargesOneYearApartClassifyAsYearlyNotMonthly() {
        // This is the exact case the user's "count >= 2 = monthly" rule gets
        // wrong: a genuine annual renewal can appear twice in a 13-month window.
        let now = Date()
        let dates = [364, 0].map { date(daysAgo: Double($0), from: now) }
        let result = SubscriptionsView.Sub.classify(dates: dates, amount: 119.88, dataHorizonDays: 400, now: now)
        XCTAssertEqual(result.cadence, .yearly)
        XCTAssertEqual(result.confidence, .likely)
        XCTAssertEqual(result.monthlyEquivalent, 119.88 / 12, accuracy: 0.01)
    }

    func testTwoChargesNinetyOneDaysApartClassifyAsQuarterly() {
        let now = Date()
        let dates = [91, 0].map { date(daysAgo: Double($0), from: now) }
        let result = SubscriptionsView.Sub.classify(dates: dates, amount: 30.0, dataHorizonDays: 400, now: now)
        XCTAssertEqual(result.cadence, .quarterly)
        XCTAssertEqual(result.monthlyEquivalent, 10.0, accuracy: 0.01)
    }

    func testSingleRecentChargeAssumesMonthly() {
        let now = Date()
        let dates = [date(daysAgo: 10, from: now)]
        let result = SubscriptionsView.Sub.classify(dates: dates, amount: 14.99, dataHorizonDays: 400, now: now)
        XCTAssertEqual(result.cadence, .monthly)
        XCTAssertEqual(result.confidence, .assumed)
    }

    func testSingleOldChargeAssumesYearly() {
        let now = Date()
        let dates = [date(daysAgo: 300, from: now)]
        let result = SubscriptionsView.Sub.classify(dates: dates, amount: 119.88, dataHorizonDays: 400, now: now)
        XCTAssertEqual(result.cadence, .yearly)
        XCTAssertEqual(result.confidence, .assumed)
    }

    func testSingleRecentChargeWithShortSyncHistoryStillAssumesMonthly() {
        // Guard: if we've only synced 20 days of history, we haven't had time
        // to observe a second charge for *any* cadence, so don't assume yearly
        // just because the merchant only appeared once.
        let now = Date()
        let dates = [date(daysAgo: 10, from: now)]
        let result = SubscriptionsView.Sub.classify(dates: dates, amount: 119.88, dataHorizonDays: 20, now: now)
        XCTAssertEqual(result.cadence, .monthly)
        XCTAssertEqual(result.confidence, .assumed)
    }

    func testMonthlyChargesWithOneSkippedCycleStillClassifyAsMonthlyViaMedian() {
        // Gaps of 30, 60, 30 days (one missed/late cycle) — the median (30)
        // should win over the outlier, unlike a mean-based approach.
        let now = Date()
        let dates = [120, 90, 30, 0].map { date(daysAgo: Double($0), from: now) }
        let result = SubscriptionsView.Sub.classify(dates: dates, amount: 9.99, dataHorizonDays: 400, now: now)
        XCTAssertEqual(result.cadence, .monthly)
    }

    func testStaleSubscriptionIsFlaggedAndExcludedFromTotal() {
        let now = Date()
        // Monthly cadence (30-day gaps), but the last charge was 100 days ago
        // — well past 2.5x the expected 30-day interval, so likely cancelled.
        let dates = [160, 130, 100].map { date(daysAgo: Double($0), from: now) }
        let result = SubscriptionsView.Sub.classify(dates: dates, amount: 9.99, dataHorizonDays: 400, now: now)
        XCTAssertTrue(result.isStale)
    }
}
