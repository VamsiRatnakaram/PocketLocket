import XCTest
@testable import PocketLocketWidgetTests

/// The ring's segment math: where each category's color starts and stops.
///
/// These are the assertions that matter because the layout is derived, not
/// authored. If the shares are mis-scaled, the ring quietly lies about the
/// budget split and nothing else on screen contradicts it.
final class WidgetRingSegmentTests: XCTestCase {

    private func category(_ category: SpendCategory, _ share: Double) -> WidgetCategory {
        WidgetCategory(category: category, amount: nil, share: share)
    }

    // MARK: - Arc length

    /// The ring is still a *budget* ring: at 60% of budget the arc covers 60%
    /// of the circle, no matter how many categories are in it.
    func testArcLengthFollowsBudgetFractionNotCategoryShares() {
        let segments = WidgetRingSegments.make(
            fraction: 0.6,
            categories: [category(.housing, 1.0)],
            limit: 3
        )
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].start, 0, accuracy: 1e-9)
        XCTAssertEqual(segments[0].end, 0.6, accuracy: 1e-9)
    }

    func testFullBudgetFillsOneLap() {
        let segments = WidgetRingSegments.make(
            fraction: 1.0,
            categories: [category(.housing, 0.5), category(.groceries, 0.5)],
            limit: 3
        )
        XCTAssertEqual(segments.first?.start ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(segments.last?.end ?? -1, 1, accuracy: 1e-9)
    }

    /// Over budget must not draw past 12 o'clock; the second lap is the view's
    /// red overflow, drawn separately on top of these.
    func testOverBudgetClampsToASingleLap() {
        let segments = WidgetRingSegments.make(
            fraction: 1.8,
            categories: [category(.shopping, 1.0)],
            limit: 3
        )
        XCTAssertEqual(segments.last?.end ?? -1, 1, accuracy: 1e-9)
    }

    func testNoBudgetOrNoSpendProducesNoSegments() {
        XCTAssertTrue(WidgetRingSegments.make(fraction: nil, categories: [category(.housing, 1)], limit: 3).isEmpty)
        XCTAssertTrue(WidgetRingSegments.make(fraction: 0, categories: [category(.housing, 1)], limit: 3).isEmpty)
        XCTAssertTrue(WidgetRingSegments.make(fraction: -0.5, categories: [category(.housing, 1)], limit: 3).isEmpty)
        XCTAssertTrue(WidgetRingSegments.make(fraction: 0.5, categories: [], limit: 3).isEmpty)
    }

    // MARK: - Proportions

    /// Three categories at 50/30/20 must come out 50/30/20 of the arc.
    func testSegmentsAreProportionalToShares() {
        let segments = WidgetRingSegments.make(
            fraction: 1.0,
            categories: [category(.housing, 0.5), category(.groceries, 0.3), category(.food, 0.2)],
            limit: 3
        )
        XCTAssertEqual(segments.count, 3)
        // Segments are exact: no gap is reserved, so widths are the shares
        // themselves. The rounded boundary is drawn by the view (overlapping
        // round caps), which is why the model can stay exact.
        XCTAssertEqual(segments[0].width, 0.5, accuracy: 1e-9)
        XCTAssertEqual(segments[1].width, 0.3, accuracy: 1e-9)
        XCTAssertEqual(segments[2].width, 0.2, accuracy: 1e-9)
        // Contiguous: every boundary meets the next segment exactly.
        for i in 1..<segments.count {
            XCTAssertEqual(segments[i].start, segments[i - 1].end, accuracy: 1e-9)
        }
    }

    /// A trimmed category list leaves a real remainder, and it must stay on the
    /// ring as the unattributed segment rather than being folded into a named
    /// category — otherwise the ring claims the named ones explain everything.
    func testTrimmedCategoriesLeaveAnUnattributedSegment() {
        let segments = WidgetRingSegments.make(
            fraction: 1.0,
            categories: [category(.housing, 0.4), category(.groceries, 0.2)],
            limit: 3
        )
        XCTAssertEqual(segments.count, 3, "two named categories plus the remainder")
        XCTAssertNil(segments.last?.category, "the tail is the unattributed remainder")
        XCTAssertEqual(segments.last?.width ?? -1, 0.4, accuracy: 1e-9)
    }

    /// A limit smaller than the category list folds the rest into the
    /// remainder, so the medium widget's three-row legend still explains the
    /// whole arc.
    func testLimitCapsNamedCategoriesAndFoldsTheRestIntoTheRemainder() {
        let many = (0..<6).map { category([.housing, .groceries, .food, .transport, .shopping, .travel][($0 * 2) % 6], 1.0 / 6.0) }
        let segments = WidgetRingSegments.make(fraction: 1.0, categories: many, limit: 3)
        let named = segments.filter { $0.category != nil }
        XCTAssertEqual(named.count, 3)
        XCTAssertNil(segments.last?.category)
        XCTAssertEqual(segments.last?.end ?? -1, 1, accuracy: 1e-6)
    }

    /// Shares that overshoot 1 (a corrupt or hand-edited payload) must be
    /// scaled into the arc, not allowed to run past 12 o'clock.
    func testOvershootingSharesAreScaledIntoTheArc() {
        let segments = WidgetRingSegments.make(
            fraction: 0.5,
            categories: [category(.housing, 1.5), category(.groceries, 1.5)],
            limit: 3
        )
        XCTAssertEqual(segments.last?.end ?? -1, 0.5, accuracy: 1e-6)
        XCTAssertFalse(segments.contains { $0.category == nil }, "nothing left over to attribute")
    }

    // MARK: - Boundaries

    /// Segments butt together: the rounded boundary is drawn by overlapping
    /// round caps in the view, not by a gap in the model. So the model's job is
    /// to be exactly contiguous, and the arc's own ends stay at 12 o'clock.
    func testSegmentsAreContiguousAndTheArcEndsAreFlush() {
        let segments = WidgetRingSegments.make(
            fraction: 1.0,
            categories: [category(.housing, 0.5), category(.groceries, 0.5)],
            limit: 3
        )
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[1].start, segments[0].end, accuracy: 1e-9, "no gap to reserve")
        XCTAssertEqual(segments[0].start, 0, accuracy: 1e-9, "arc still starts at 12 o'clock")
        XCTAssertEqual(segments[1].end, 1, accuracy: 1e-9, "arc still ends at 12 o'clock")
    }

    /// Regression guard for a bug caught by looking at the rendered PNG: the
    /// large widget listed a 5%-of-spend Transport row, but because the old
    /// model reserved a ~0.04 gap per boundary the segment was narrower than its
    /// own gap and got dropped — leaving a legend row with no color on the ring.
    ///
    /// Overlapping caps removed the gap entirely, so no segment can be dropped
    /// for being thin. A category too narrow to see is a legibility problem; a
    /// category that vanishes is a lying legend.
    func testThinCategoryIsNeverDropped() {
        // Shares sum to 1 so there's no unattributed remainder to account for
        // and the assertion is only about the thin category surviving.
        let segments = WidgetRingSegments.make(
            fraction: 0.75,
            categories: [
                category(.housing, 0.70), category(.groceries, 0.13),
                category(.food, 0.12), category(.transport, 0.05)
            ],
            limit: 4
        )
        XCTAssertEqual(segments.count, 4, "every named category keeps a segment")
        XCTAssertTrue(segments.allSatisfy { $0.width > 0 }, "none may run backwards")
        // Even at 0.0375 of a turn — below the ~0.04 gap the old model reserved
        // per boundary, which is what used to drop it — Transport still draws.
        XCTAssertEqual(segments.last?.category, .transport)
        XCTAssertEqual(segments.last?.width ?? -1, 0.0375, accuracy: 1e-9)
        // Shares summing to 1 leave a few ulps of "remainder"; that's floating-
        // point dust, not a category, and it gets folded back rather than
        // emitted as a degenerate segment.
        XCTAssertEqual(segments.last?.end ?? -1, 0.75, accuracy: 1e-9, "arc ends exactly on budget")
    }

    /// A sliver so thin it is arithmetically zero must not survive as a segment
    /// running backwards.
    func testZeroWidthSegmentsAreNotEmitted() {
        let segments = WidgetRingSegments.make(
            fraction: 0.02,
            categories: [category(.housing, 1.0), category(.groceries, 0.0)],
            limit: 3
        )
        XCTAssertTrue(segments.allSatisfy { $0.width > 0 }, "none may run backwards")
    }

    /// Every segment must be drawable: start strictly before end, both inside
    /// the circle.
    func testEverySegmentIsDrawable() {
        let segments = WidgetRingSegments.make(
            fraction: 0.73,
            categories: [
                category(.housing, 0.41), category(.groceries, 0.19),
                category(.food, 0.14), category(.transport, 0.09),
                category(.entertainment, 0.06)
            ],
            limit: 4
        )
        XCTAssertFalse(segments.isEmpty)
        for segment in segments {
            XCTAssertGreaterThan(segment.end, segment.start)
            XCTAssertGreaterThanOrEqual(segment.start, 0)
            XCTAssertLessThanOrEqual(segment.end, 1)
        }
    }
}
