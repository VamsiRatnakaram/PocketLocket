import SwiftUI

/// A selectable category cell used in the categorize sheet.
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
                            .font(.caption2.weight(.bold))
                            .padding(5)
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
        VStack(spacing: 4) {
            Image(systemName: category.symbol)
                .font(.body.weight(.medium))
            Text(category.displayName)
                .font(.caption2)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(4)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    /// A softened tint keeps selection clear without making the glass read as
    /// an opaque color tile.
    private var glassTint: Color? {
        isSelected ? category.tint.opacity(0.72) : nil
    }
}
