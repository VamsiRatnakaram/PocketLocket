import SwiftUI

struct TransactionRow: View {
    let txn: TransactionRecord
    let category: SpendCategory

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(category.tint.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: category.symbol)
                    .foregroundStyle(category.tint)
                    .contentTransition(.symbolEffect(.replace))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(txn.title)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(txn.date, format: .dateTime.month().day())
                    if txn.pending {
                        Text("• Pending").foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(amountText)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(txn.amount > 0 ? Color.primary : Color.green)
        }
        .padding(.vertical, 2)
    }

    /// Plaid convention: positive = money out (spend), negative = money in.
    private var amountText: String {
        let magnitude = CurrencyFormatter.string(abs(txn.amount), code: txn.isoCurrencyCode)
        return txn.amount > 0 ? "-\(magnitude)" : "+\(magnitude)"
    }
}
