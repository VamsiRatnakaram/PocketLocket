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
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .layoutPriority(1)

            Spacer()

            Text(CurrencyFormatter.string(account.currentBalance, code: account.isoCurrencyCode))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
