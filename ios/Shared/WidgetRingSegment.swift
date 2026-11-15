import Foundation

/// One colored slice of the widget's budget ring.
///
/// A segment is expressed in circle coordinates (0...1 of a full turn, 0 being
/// 12 o'clock), the same space `Circle().trim(from:to:)` takes, so the view can
/// draw one straight from this without any further trigonometry.
struct WidgetRingSegment: Equatable, Sendable {
    /// `nil` is the unattributed remainder: money spent in categories that
    /// didn't make it into the snapshot's top list. It gets its own segment
    /// rather than being silently absorbed, so the ring never implies the named
    /// categories explain the whole arc.
    let category: SpendCategory?
    let start: Double
    let end: Double

    var width: Double { end - start }
}

/// Turns a snapshot's category shares into ring segments.
///
/// The ring stays a *budget* ring: the arc still only fills to `fraction` of
/// the circle, which is the one thing the widget has to say at a glance. What
/// changes is that the filled part is divided up by category instead of being
/// one flat color. So the two readings don't compete — length answers "how much
/// of my budget is gone", color answers "on what".
enum WidgetRingSegments {
    /// How many categories the ring is allowed to name.
    ///
    /// The medium widget lists three rows, and the ring is its legend — more
    /// colors than rows would put unexplained hues on screen. It's also the
    /// legibility limit at 104pt: a fifth sliver is a few pixels of arc. The
    /// rest folds into the unattributed segment, so nothing is hidden, just
    /// not named.
    static let displayedCategories = 3

    /// Builds the segments for one ring.
    ///
    /// Segments are **contiguous** — each one ends exactly where the next
    /// begins, with no gap between them. The rounded look comes from the view:
    /// it draws them last-to-first, so each category's round cap is painted over
    /// the top of the following segment. That reads as a soft overlap rather than
    /// a hard cut, and it means the model never has to reserve arc for a gap, so
    /// a thin category can never be dropped for being narrower than its own gap.
    ///
    /// - Parameter fraction: `totalSpent / monthlyBudget`, unclamped and nil
    ///   when no budget is set. The arc is clamped to a single lap; the overflow
    ///   lap is drawn separately by the view, in red, on top of this.
    /// - Parameter categories: the snapshot's rows, already largest-first and
    ///   already trimmed. Their `share`s are shares of *total spend*, so they
    ///   sum to 1 only when no category was trimmed off.
    static func make(
        fraction: Double?,
        categories: [WidgetCategory],
        limit: Int = displayedCategories
    ) -> [WidgetRingSegment] {
        let arc = min(max(fraction ?? 0, 0), 1)
        guard arc > 0 else { return [] }

        let usable = categories.prefix(max(limit, 0)).filter { $0.share > 0 }
        guard !usable.isEmpty else { return [] }

        // Shares are relative to total spend, so a trimmed list leaves a
        // genuine remainder. Dividing by max(sum, 1) instead of sum means a
        // well-behaved list keeps that remainder visible, while a corrupt one
        // that overshoots still gets scaled into the arc rather than overflowing
        // past 12 o'clock.
        let sum = usable.reduce(0) { $0 + min($1.share, 1) }
        guard sum > 0 else { return [] }
        let denominator = max(sum, 1)

        var segments: [WidgetRingSegment] = []
        segments.reserveCapacity(usable.count + 1)
        var cursor = 0.0
        for item in usable {
            let width = arc * min(item.share, 1) / denominator
            // Floating-point drift across many categories can make the last
            // boundary land a hair past the arc; clamp so the arc never grows.
            let end = min(cursor + width, arc)
            if end > cursor {
                segments.append(WidgetRingSegment(category: item.category, start: cursor, end: end))
            }
            cursor = end
        }

        // Whatever the named categories don't account for is still spend.
        //
        // Shares that sum to 1 leave the cursor a few ulps short of `arc`
        // through no fault of the data, and a 1e-16 segment is a degenerate
        // artifact rather than a real reading. So a numerically-zero remainder
        // is folded back into the last segment instead of being emitted.
        let remainder = arc - cursor
        if remainder > Self.minVisibleArc {
            segments.append(WidgetRingSegment(category: nil, start: cursor, end: arc))
        } else if let last = segments.last, last.end < arc {
            segments[segments.count - 1] = WidgetRingSegment(category: last.category, start: last.start, end: arc)
        }

        return segments
    }

    /// Below this, an arc isn't a category — it's floating-point dust.
    private static let minVisibleArc = 1e-9
}
