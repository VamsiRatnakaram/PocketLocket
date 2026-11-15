import SwiftUI
import WidgetKit

/// Home Screen layouts.
///
/// Nothing here fetches or computes: each view takes a `BudgetEntry` and draws
/// it. The empty states are drawn with the same care as the populated ones
/// because a fresh install shows them, and a widget that looks broken on day
/// one never gets added.
struct BudgetWidgetEntryView: View {
    let entry: BudgetEntry
    /// `nil` asks the environment, which is how WidgetKit tells a widget which
    /// size it is. Tests pass one explicitly: `\.widgetFamily` is read-only, so
    /// there is no other way to render the medium layout in a test host.
    var familyOverride: WidgetFamily?

    @Environment(\.widgetFamily) private var environmentFamily

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    init(entry: BudgetEntry, family: WidgetFamily? = nil) {
        self.entry = entry
        self.familyOverride = family
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallBudgetView(entry: entry)
            case .systemMedium:
                MediumBudgetView(entry: entry)
            case .systemLarge:
                LargeBudgetView(entry: entry)
            case .accessoryCircular:
                CircularBudgetView(entry: entry)
            case .accessoryRectangular:
                RectangularBudgetView(entry: entry)
            default:
                SmallBudgetView(entry: entry)
            }
        }
        .modifier(WidgetBackground(family: family))
    }
}

/// The one background rule, kept in a modifier so no layout forgets it.
///
/// iOS 17 requires a widget to supply its own background; without one, a user
/// who picks the transparent Smart Stack style gets unreadable text over their
/// wallpaper. For the Lock Screen families the system draws the material, so we
/// hand it `AccessoryWidgetBackground()` and stay out of the way.
private struct WidgetBackground: ViewModifier {
    let family: WidgetFamily
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            if renderingMode == .fullColor && !family.isAccessory {
                LinearGradient(
                    colors: [
                        WidgetPalette.accent.opacity(0.14),
                        WidgetPalette.accent.opacity(0.02)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .background(Color(.systemBackground))
            } else {
                AccessoryWidgetBackground()
            }
        }
    }
}

extension WidgetFamily {
    fileprivate var isAccessory: Bool {
        self == .accessoryCircular || self == .accessoryRectangular || self == .accessoryInline
    }
}

// MARK: - Small

/// Ring with the headline in its hole, and the metric cycle button in the
/// corner. One interactive element, which is all iOS 17 allows per widget.
struct SmallBudgetView: View {
    let entry: BudgetEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let readout = entry.readout {
                ZStack {
                    WidgetRing(
                        fraction: snapshot.fraction ?? 0,
                        lineWidth: 9,
                        segments: entry.ringSegments()
                    )
                    .padding(2)

                    WidgetHeadline(readout: readout, centerIn: 62)
                }
                .overlay(alignment: .bottomTrailing) {
                    MetricCycleButton()
                        .padding(4)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText(readout, snapshot: snapshot))
            } else {
                WidgetEmptyState(compact: true)
            }
        }
        .widgetURL(WidgetDeepLink.home())
    }

    private func accessibilityText(_ readout: WidgetReadout, snapshot: WidgetSnapshot) -> String {
        var text = "\(WidgetText.month(snapshot.monthStart, wide: true)) budget: \(readout.headline), \(readout.caption)"
        if !snapshot.categories.isEmpty {
            text += ". Top categories " + snapshot.categories.prefix(3).map(\.category.displayName).joined(separator: ", ")
        }
        return text
    }
}

/// Cycles the shared metric. Writes a preference and asks WidgetKit to redraw;
/// the intent itself is declared next to the widget so both targets share it.
struct MetricCycleButton: View {
    var body: some View {
        Button(intent: CycleWidgetMetricIntent()) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(5)
                .background(Circle().fill(.thinMaterial))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change the budget figure shown")
    }
}

// MARK: - Medium

/// Ring on the left, top categories on the right — the layout most people will
/// actually keep, because it answers "how am I doing" and "on what" at once.
struct MediumBudgetView: View {
    let entry: BudgetEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let readout = entry.readout {
                HStack(spacing: 14) {
                    ZStack {
                        WidgetRing(fraction: snapshot.fraction ?? 0, lineWidth: 11, segments: entry.ringSegments())
                        WidgetHeadline(readout: readout, centerIn: 74)
                    }
                    .frame(width: 104, height: 104)

                    VStack(alignment: .leading, spacing: 8) {
                        MonthTitle(date: snapshot.monthStart)
                        if snapshot.categories.isEmpty {
                            Spacer(minLength: 0)
                            Text("No spending recorded yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        } else {
                            WidgetCategoryRows(
                                categories: Array(snapshot.categories.prefix(3)),
                                currencyCode: snapshot.isoCurrencyCode,
                                showsAmounts: snapshot.showsAmounts
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText(readout, snapshot: snapshot))
            } else {
                WidgetEmptyState(compact: false)
            }
        }
        .widgetURL(WidgetDeepLink.home())
    }

    private func accessibilityText(_ readout: WidgetReadout, snapshot: WidgetSnapshot) -> String {
        var text = "\(WidgetText.month(snapshot.monthStart, wide: true)) budget: \(readout.headline), \(readout.caption)"
        if !snapshot.categories.isEmpty {
            text += ". " + snapshot.categories.prefix(3).map { row in
                let value = snapshot.showsAmounts && row.amount != nil
                    ? WidgetText.money(row.amount ?? 0, code: snapshot.isoCurrencyCode)
                    : WidgetText.percent(row.share)
                return "\(row.category.displayName) \(value)"
            }.joined(separator: ", ")
        }
        return text
    }
}

// MARK: - Large

/// The full month: headline, ring, and every category the snapshot carries.
struct LargeBudgetView: View {
    let entry: BudgetEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let readout = entry.readout {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            MonthTitle(date: snapshot.monthStart)
                            Text(readout.headline)
                                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(readout.isOver ? WidgetPalette.overRed : .primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Text(readout.caption)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        ZStack {
                            // The large layout lists every category it carries,
                            // so the ring may name them all: every color on the
                            // arc has a row beside it.
                            WidgetRing(
                                fraction: snapshot.fraction ?? 0,
                                lineWidth: 10,
                                segments: entry.ringSegments(limit: snapshot.categories.count)
                            )
                            if snapshot.hasBudget {
                                Text(WidgetText.percent(min(max(snapshot.fraction ?? 0, 0), 1)))
                                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 74, height: 74)
                    }

                    if snapshot.categories.isEmpty {
                        Spacer(minLength: 0)
                        Text("No spending recorded this month.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    } else {
                        Divider()
                        WidgetCategoryRows(
                            categories: snapshot.categories,
                            currencyCode: snapshot.isoCurrencyCode,
                            showsAmounts: snapshot.showsAmounts
                        )
                        Spacer(minLength: 0)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText(readout, snapshot: snapshot))
            } else {
                WidgetEmptyState(compact: false)
            }
        }
        .widgetURL(WidgetDeepLink.home())
    }

    private func accessibilityText(_ readout: WidgetReadout, snapshot: WidgetSnapshot) -> String {
        var text = "\(WidgetText.month(snapshot.monthStart, wide: true)) budget: \(readout.headline), \(readout.caption)"
        if !snapshot.categories.isEmpty {
            text += ". " + snapshot.categories.map { row in
                let value = snapshot.showsAmounts && row.amount != nil
                    ? WidgetText.money(row.amount ?? 0, code: snapshot.isoCurrencyCode)
                    : WidgetText.percent(row.share)
                return "\(row.category.displayName) \(value)"
            }.joined(separator: ", ")
        }
        return text
    }
}

// MARK: - Lock Screen

/// Circular: the system wants a gauge here, so this is the one place that uses
/// `Gauge` instead of the brand ring. It monochromes itself automatically.
struct CircularBudgetView: View {
    let entry: BudgetEntry

    var body: some View {
        if let snapshot = entry.snapshot, let fraction = snapshot.fraction {
            Gauge(value: min(max(fraction, 0), 1), in: 0...1) {
                Text(verbatim: "Spent")
            } currentValueLabel: {
                Text(WidgetText.percent(max(0, fraction)))
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetURL(WidgetDeepLink.home())
        } else {
            // No budget to measure against: a ring of nothing would read as an
            // error, so fall back to the raw spend share of the month.
            Image(systemName: "chart.pie")
                .accessibilityLabel("PocketLocket: no budget set")
        }
    }
}

/// Rectangular: the headline plus the two biggest categories, all in percentages
/// unless the user has turned amounts on.
struct RectangularBudgetView: View {
    let entry: BudgetEntry

    var body: some View {
        if let snapshot = entry.snapshot, let readout = entry.readout {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(readout.headline)
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(readout.caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if !snapshot.categories.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(snapshot.categories.prefix(2))) { row in
                            Label {
                                Text(shortLabel(row, snapshot: snapshot))
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            } icon: {
                                Image(systemName: row.category.symbol)
                                    .font(.caption2)
                            }
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .widgetURL(WidgetDeepLink.home())
        } else {
            Label("PocketLocket", systemImage: "chart.pie")
        }
    }

    private func shortLabel(_ row: WidgetCategory, snapshot: WidgetSnapshot) -> String {
        if snapshot.showsAmounts, let amount = row.amount {
            return "\(row.category.displayName) \(WidgetText.money(amount, code: snapshot.isoCurrencyCode))"
        }
        return "\(row.category.displayName) \(WidgetText.percent(row.share))"
    }
}

// MARK: - Shared bits

private struct MonthTitle: View {
    let date: Date
    var body: some View {
        Text(WidgetText.month(date, wide: true))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

/// What a widget shows before the app has ever written a snapshot, or after
/// *Reset local data*. Says what to do rather than showing a zero.
struct WidgetEmptyState: View {
    let compact: Bool
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: family == .systemLarge ? .leading : .center, spacing: 6) {
            Image(systemName: "chart.pie")
                .font(compact ? .title3 : .title2)
                .foregroundStyle(.secondary)
            Text(compact ? "No budget yet" : "Set a budget")
                .font(compact ? .caption2.weight(.semibold) : .headline)
                .multilineTextAlignment(family == .systemLarge ? .leading : .center)
            if !compact {
                Text("Open PocketLocket to set a monthly budget. Your widgets fill in after that.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("PocketLocket: no budget set yet. Open the app to set one.")
        .widgetURL(WidgetDeepLink.home())
    }
}
