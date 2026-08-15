import SwiftUI

/// A selectable category cell used in the categorize sheet. Springs up, tints,
/// and bounces its symbol when selected for a tactile, award-worthy feel.
struct CategoryChip: View {
    let category: SpendCategory
    let isSelected: Bool

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            label
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .padding(8)
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(.primary)
                .glassEffect(.regular.tint(glassTint).interactive(), in: shape)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            label
                .background(
                    isSelected ? category.tint.opacity(0.20) : Color(.secondarySystemBackground),
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(isSelected ? category.tint : .clear, lineWidth: 2)
                }
                .foregroundStyle(isSelected ? category.tint : .primary)
                .scaleEffect(isSelected ? 1.04 : 1)
                .shadow(color: isSelected ? category.tint.opacity(0.3) : .clear, radius: 8, y: 3)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    private var label: some View {
        VStack(spacing: 6) {
            Image(systemName: category.symbol)
                .font(.title3)
                .symbolEffect(.bounce, value: isSelected)
            Text(category.displayName)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 74)
        .padding(8)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    /// A softened tint keeps selection clear without making the glass read as
    /// an opaque color tile.
    private var glassTint: Color? {
        isSelected ? category.tint.opacity(0.72) : nil
    }
}
