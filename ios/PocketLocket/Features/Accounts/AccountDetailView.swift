import SwiftData
import SwiftUI

struct AccountDetailView: View {
    let account: AccountRecord

    @Query(sort: \TransactionRecord.date, order: .reverse)
    private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
    @State private var detail: TransactionRecord?

    init(account: AccountRecord) {
        self.account = account
        let accountID = account.id
        _transactions = Query(
            filter: #Predicate<TransactionRecord> { $0.accountId == accountID },
            sort: \TransactionRecord.date,
            order: .reverse
        )
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.displayName)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let officialName = account.officialName,
                       officialName != account.name {
                        Text(account.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Balances") {
                LabeledContent("Current") {
                    balance(account.currentBalance)
                }
                if let available = account.availableBalance {
                    LabeledContent("Available") {
                        balance(available)
                    }
                }
            }

            Section("Account") {
                LabeledContent("Type", value: accountType)
                if let mask = account.mask, !mask.isEmpty {
                    LabeledContent("Number", value: "••••\(mask)")
                }
                LabeledContent("Currency", value: account.isoCurrencyCode.uppercased())
            }

            Section {
                if transactions.isEmpty {
                    ContentUnavailableView(
                        "No transactions",
                        systemImage: "list.bullet",
                        description: Text("Transactions for this account will appear here.")
                    )
                } else {
                    ForEach(transactions) { transaction in
                        Button { detail = transaction } label: {
                            TransactionRow(
                                txn: transaction,
                                category: transaction.resolvedCategory(using: rules)
                            )
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                    }
                }
            } header: {
                Text(
                    "\(transactions.count) transaction"
                        + "\(transactions.count == 1 ? "" : "s")"
                )
            }
        }
        .listStyle(.plain)
        .navigationTitle("Account Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { transaction in
            TransactionDetailView(
                txn: transaction,
                currentCategory: transaction.resolvedCategory(using: rules)
            )
        }
    }

    private var accountType: String {
        (account.subtype ?? account.type ?? "Account")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func balance(_ amount: Double) -> some View {
        Text(CurrencyFormatter.string(amount, code: account.isoCurrencyCode))
            .fontWeight(.semibold)
            .monospacedDigit()
    }
}
