import SwiftUI

/// A single progress ring showing total budget used, with a percentage in the
/// center. The per-category bars live in `CategoryBreakdownList` below it.
struct SpendRingProgress: View {
    let totalSpent: Double
    let monthlyBudget: Double

    /// Unclamped fraction of the budget used (can exceed 1 when over budget).
    private var fraction: Double {
        guard monthlyBudget > 0 else { return 0 }
        return max(0, totalSpent / monthlyBudget)
    }
    private var isOver: Bool { fraction > 1 }
    private var firstLap: Double { min(fraction, 1) }
    /// The portion beyond 100%, drawn as a second lap (0...1).
    private var overflow: Double { min(max(fraction - 1, 0), 1) }

    @State private var animatedFirst: Double = 0
    @State private var animatedOverflow: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 24)

            // First lap — up to 100% of budget (turns amber once you go over).
            Circle()
                .trim(from: 0, to: animatedFirst)
                .stroke(
                    isOver ? Color.orange : Color.accentColor,
                    style: StrokeStyle(lineWidth: 24, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Overflow lap — how far past budget you are, layered on top in red.
            if isOver {
                Circle()
                    .trim(from: 0, to: animatedOverflow)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 24, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .red.opacity(0.4), radius: 6)
            }

            VStack(spacing: 3) {
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(isOver ? .red : .primary)
                if isOver {
                    Text("\(CurrencyFormatter.string(totalSpent - monthlyBudget)) over")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                } else {
                    Text("\(CurrencyFormatter.string(totalSpent)) of \(CurrencyFormatter.compact(monthlyBudget))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28)
            .multilineTextAlignment(.center)
        }
        .frame(width: 240, height: 240)
        .frame(maxWidth: .infinity)
        .onAppear { animate() }
        .onChange(of: fraction) { _, _ in animate() }
    }

    private func animate() {
        withAnimation(.easeOut(duration: 0.7)) {
            animatedFirst = firstLap
            animatedOverflow = overflow
        }
    }
}
