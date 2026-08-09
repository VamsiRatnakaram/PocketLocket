import SwiftUI

/// A selectable category cell used in the categorize sheet. Springs up, tints,
/// and bounces its symbol when selected for a tactile, award-worthy feel.
struct CategoryChip: View {
    let category: SpendCategory
    let isSelected: Bool

    var body: some View {
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
        .background(
            isSelected ? category.tint.opacity(0.20) : Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? category.tint : .clear, lineWidth: 2)
        }
        .foregroundStyle(isSelected ? category.tint : .primary)
        .scaleEffect(isSelected ? 1.04 : 1)
        .shadow(color: isSelected ? category.tint.opacity(0.3) : .clear, radius: 8, y: 3)
    }
}
