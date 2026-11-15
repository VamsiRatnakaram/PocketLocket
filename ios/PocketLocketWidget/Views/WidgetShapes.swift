import SwiftUI
import WidgetKit

/// The budget ring, drawn without Swift Charts.
///
/// A widget is rendered by another process against a size it dictates, so this
/// drops everything the in-app ring does that a widget can't afford: no
/// animation, no glow, no tap geometry. What it keeps is the part that makes
/// PocketLocket recognisable — one rounded arc on a faint track, amber then red
/// past 100% — so the Home Screen and the app read as the same product.
struct WidgetRing: View {
    /// Unclamped. Over budget draws a second lap, exactly like `SpendRingProgress`.
    let fraction: Double
    let lineWidth: CGFloat
    /// When non-nil the filled arc is split into these per-category colors
    /// instead of one flat accent. `nil` (or empty) is the plain ring.
    let segments: [WidgetRingSegment]?
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var isOver: Bool { fraction > 1 }
    private var firstLap: Double { min(max(fraction, 0), 1) }
    private var overflow: Double { min(max(fraction - 1, 0), 1) }

    private var isSegmented: Bool {
        // A single-segment "ring" is the unattributed remainder only — nothing
        // to color-code, so draw the plain ring rather than an accent arc that
        // happens to be drawn by the segment path.
        segments?.contains { $0.category != nil } ?? false
    }

    /// In accented and vibrant modes the system wants a monochrome widget;
    /// `Color.primary` is what it asks for, and a tint would fight it.
    private var arcColor: Color {
        if renderingMode != .fullColor { return .primary }
        if fraction > 1.05 { return WidgetPalette.overRed }
        if isOver { return WidgetPalette.overAmber }
        return WidgetPalette.accent
    }

    /// The second lap. Plain ring: the original amber-then-red ramp.
    /// Segmented: the first lap is already telling the category story, so the
    /// overflow goes straight to red instead of recoloring the whole ring
    /// amber and throwing the category colors away.
    private var overflowColor: Color {
        if isSegmented { return WidgetPalette.overRed }
        return arcColor
    }

    init(fraction: Double, lineWidth: CGFloat = 10, segments: [WidgetRingSegment]? = nil) {
        self.fraction = fraction
        self.lineWidth = lineWidth
        self.segments = segments
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(WidgetPalette.track, lineWidth: lineWidth)

            if isSegmented, let segments {
                // Round caps, drawn last-to-first so each category's rounded end
                // is painted OVER the following segment. That's what makes a
                // boundary read as a soft overlap instead of a hard cut, and it
                // matches the single-arc ring's geometry: a trimmed `Circle` with
                // round caps already bulges half a stroke past its ends, so the
                // plain and colored rings agree on where 12 o'clock is.
                //
                // Reversed order is the whole trick, and it also means the model
                // never reserves arc for a gap — so a thin category can't be
                // dropped for being narrower than its own gap. Boundaries all
                // shift later by the same half-stroke, so proportions survive a
                // rigid shift and the arc still measures the budget honestly.
                //
                // Drawn reversed so the earliest segment is painted last, i.e.
                // on top of all the ones after it.
                Group {
                    ForEach(Array(segments.reversed().enumerated()), id: \.offset) { _, segment in
                        Circle()
                            .trim(from: segment.start, to: segment.end)
                            .stroke(
                                color(for: segment),
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                            )
                    }
                }
                .rotationEffect(.degrees(-90))
                // Same treatment the plain arc gets, so a tinted Smart Stack
                // look can accent the whole ring rather than parts of it.
                .widgetAccentable()
            } else {
                Circle()
                    .trim(from: 0, to: firstLap)
                    .stroke(arcColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    // Lets the system apply its own accent treatment to the arc when
                    // the user picks a tinted Smart Stack look.
                    .widgetAccentable()
            }

            if isOver {
                Circle()
                    .trim(from: 0, to: overflow)
                    .stroke(overflowColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    /// Category colors are the same tints the rows and the app use, so a blue
    /// arc segment and the blue "Housing" row are visibly the same thing.
    ///
    /// The unattributed remainder gets a neutral, deliberately *not* the brand
    /// blue: that is already Housing's color, and two blue arcs on one ring
    /// read as one category that has somehow come back.
    private func color(for segment: WidgetRingSegment) -> Color {
        guard renderingMode == .fullColor else { return .primary }
        return segment.category?.tint ?? WidgetPalette.unattributed
    }
}

/// The headline number plus its caption.
///
/// Widgets have no scroll and no truncation tolerance, and Dynamic Type on a
/// Home Screen can be enormous, so the headline shrinks rather than clipping.
struct WidgetHeadline: View {
    let readout: WidgetReadout
    /// Constrains the text to the diameter of a ring's hole, used by the small
    /// widget where the number sits inside the arc.
    var centerIn: CGFloat?

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var color: Color {
        guard renderingMode == .fullColor else { return .primary }
        return readout.isOver ? WidgetPalette.overRed : .primary
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(readout.headline)
                .font(.system(.title, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(readout.caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: centerIn)
    }
}

/// Rows of categories with a share bar each.
///
/// Percent-first by design: without amounts a row is a name and a bar, and with
/// them it gains a figure. The hidden variant is what makes the Lock Screen
/// placement safe to leave on all day.
struct WidgetCategoryRows: View {
    let categories: [WidgetCategory]
    let currencyCode: String
    let showsAmounts: Bool

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(categories) { item in
                if let url = WidgetDeepLink.category(item.category) {
                    // `Link` rather than `widgetURL` so a row can name its own
                    // destination; the surrounding `widgetURL` still covers every
                    // tap that lands on none of them.
                    Link(destination: url) { row(item) }
                        .buttonStyle(.plain)
                } else {
                    row(item)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func row(_ item: WidgetCategory) -> some View {
        HStack(spacing: 7) {
            Image(systemName: item.category.symbol)
                .font(.caption2)
                .foregroundStyle(tint(for: item.category))
                .frame(width: 13)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(item.category.displayName)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    if showsAmounts, let amount = item.amount {
                        Text(WidgetText.money(amount, code: currencyCode))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    } else {
                        Text(WidgetText.percent(item.share))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(WidgetPalette.track)
                        Capsule()
                            .fill(tint(for: item.category))
                            .frame(width: max(2, proxy.size.width * min(max(item.share, 0), 1)))
                    }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityRow(item))
    }

    private func tint(for category: SpendCategory) -> Color {
        renderingMode == .fullColor ? category.tint : .primary
    }

    private func accessibilityRow(_ item: WidgetCategory) -> String {
        if showsAmounts, let amount = item.amount {
            return "\(item.category.displayName), \(WidgetText.money(amount, code: currencyCode))"
        }
        return "\(item.category.displayName), \(WidgetText.percent(item.share)) of spending"
    }
}
