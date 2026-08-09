import SwiftUI
import Charts

/// Hero ring — a segmented donut where each arc is a category's share of spend.
/// The center shows total spent vs. the monthly budget.
struct SpendRingView: View {
    let spends: [CategorySpend]
    let totalSpent: Double
    let monthlyBudget: Double
    var onSelect: ((SpendCategory) -> Void)? = nil

    private let ringSize: CGFloat = 240

    var body: some View {
        ZStack {
            // Soft hero glow behind the ring for depth (tinted by the top category).
            if let top = spends.first {
                Circle()
                    .fill(top.category.tint.opacity(0.18))
                    .frame(width: 200, height: 200)
                    .blur(radius: 44)
            }
            if spends.isEmpty {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 26)
                    .frame(width: 220, height: 220)
            } else {
                Chart(spends) { spend in
                    SectorMark(
                        angle: .value("Spend", spend.amount),
                        innerRadius: .ratio(0.64),
                        angularInset: 1.5
                    )
                    .cornerRadius(5)
                    .foregroundStyle(spend.category.tint)
                }
                .chartLegend(.hidden)
                .frame(width: ringSize, height: ringSize)
                .contentShape(Circle())
                .onTapGesture(coordinateSpace: .local) { location in
                    handleTap(at: location)
                }
            }

            centerLabel
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Spent \(CurrencyFormatter.string(totalSpent)) of \(CurrencyFormatter.string(monthlyBudget))")
    }

    /// Resolves a deliberate tap on the donut band to its category. Uses plain
    /// geometry (not Chart selection) so scrolling never triggers a phantom tap.
    private func handleTap(at location: CGPoint) {
        guard let onSelect, !spends.isEmpty, totalSpent > 0 else { return }
        let center = ringSize / 2
        let dx = location.x - center
        let dy = location.y - center
        let radius = hypot(dx, dy)
        // Only respond to taps within the visible ring band.
        guard radius >= center * 0.6, radius <= center else { return }
        var angle = atan2(dx, -dy)               // 0 at 12 o'clock, clockwise positive
        if angle < 0 { angle += 2 * .pi }
        let target = (angle / (2 * .pi)) * totalSpent
        var cumulative = 0.0
        for spend in spends {
            cumulative += spend.amount
            if target <= cumulative { onSelect(spend.category); return }
        }
        onSelect(spends[spends.count - 1].category)
    }

    private var centerLabel: some View {
        VStack(spacing: 2) {
            Text(CurrencyFormatter.string(totalSpent))
                .font(.system(.title, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("of \(CurrencyFormatter.compact(monthlyBudget))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
