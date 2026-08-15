import SwiftUI

struct AccountCard: View {
    let account: AccountRecord

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: iconName)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(subtitle)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(
                        CurrencyFormatter.string(
                            account.currentBalance,
                            code: account.isoCurrencyCode
                        )
                    )
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let type = (account.subtype ?? account.type ?? "account").capitalized
        if let mask = account.mask { return "\(type) ••\(mask)" }
        return type
    }

    private var iconName: String {
        switch account.type {
        case "credit": return "creditcard.fill"
        case "loan": return "banknote.fill"
        case "investment": return "chart.line.uptrend.xyaxis"
        default: return "building.columns.fill"
        }
    }
}
