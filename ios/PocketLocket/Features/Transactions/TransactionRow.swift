import SwiftUI

struct TransactionRow: View {
    let txn: TransactionRecord
    let category: SpendCategory
    let reimbursedAmount: Double
    let reimbursementSourceAmount: Double
    let accountLabel: String?
    let isAccountExcluded: Bool

    init(
        txn: TransactionRecord,
        category: SpendCategory,
        reimbursedAmount: Double = 0,
        reimbursementSourceAmount: Double = 0,
        accountLabel: String? = nil,
        isAccountExcluded: Bool = false
    ) {
        self.txn = txn
        self.category = category
        self.reimbursedAmount = reimbursedAmount
        self.reimbursementSourceAmount = reimbursementSourceAmount
        self.accountLabel = accountLabel
        self.isAccountExcluded = isAccountExcluded
    }

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
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(txn.date, format: .dateTime.month().day())
                    if let accountLabel, !accountLabel.isEmpty {
                        Text("• \(accountLabel)")
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if txn.pending {
                        Text("• Pending").foregroundStyle(.orange)
                    }
                    if TransactionListBuilder.classify(txn, category: category) == .returns {
                        Text("• Return").foregroundStyle(.green)
                    }
                    if reimbursedAmount > 0.005 {
                        Text("• Reimbursed")
                            .foregroundStyle(.green)
                    }
                    if reimbursementSourceAmount > 0.005 {
                        Text("• Applied")
                            .foregroundStyle(.green)
                    }
                    // The spend ring silently drops non-spending categories.
                    // Without a marker there's no way to tell an excluded
                    // transaction from one the app simply never imported.
                    if txn.amount > 0
                        && (isAccountExcluded || !category.isSpending) {
                        Text("• Not in budget")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(txn.amount > 0 ? Color.primary : Color.green)
                if reimbursedAmount > 0.005, txn.amount > 0 {
                    Text(
                        CurrencyFormatter.string(
                            max(0, txn.amount - reimbursedAmount),
                            code: txn.isoCurrencyCode
                        ) + " net"
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else if reimbursementSourceAmount > 0.005 {
                    Text(
                        CurrencyFormatter.string(
                            reimbursementSourceAmount,
                            code: txn.isoCurrencyCode
                        ) + " applied"
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Plaid convention: positive = money out (spend), negative = money in.
    private var amountText: String {
        let magnitude = CurrencyFormatter.string(abs(txn.amount), code: txn.isoCurrencyCode)
        return txn.amount > 0 ? "-\(magnitude)" : "+\(magnitude)"
    }
}
