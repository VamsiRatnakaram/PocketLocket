import SwiftData
import SwiftUI

struct AccountDetailView: View {
    let account: AccountRecord

    @Environment(\.modelContext) private var context
    @Query(sort: \TransactionRecord.date, order: .reverse)
    private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
    @State private var detail: TransactionRecord?
    @State private var errorMessage: String?

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
                Picker("Type", selection: accountTypeBinding) {
                    Text("Automatic (\(inferredAccountType))")
                        .tag(AccountTypeChoice?.none)
                    ForEach(AccountTypeChoice.allCases) { type in
                        Text(type.displayName)
                            .tag(AccountTypeChoice?.some(type))
                    }
                }
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
        .alert(
            "Couldn’t Update Account Type",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var inferredAccountType: String {
        (account.subtype ?? account.type ?? "Account")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private var accountTypeBinding: Binding<AccountTypeChoice?> {
        Binding(
            get: {
                account.typeOverrideRaw.flatMap(AccountTypeChoice.init(rawValue:))
            },
            set: { type in
                account.typeOverrideRaw = type?.rawValue
                do {
                    try TransferMatchService.recompute(
                        in: context,
                        saveChanges: false
                    )
                    try ReimbursementAllocationService.reconcile(in: context)
                    try context.save()
                } catch {
                    context.rollback()
                    errorMessage = error.localizedDescription
                }
            }
        )
    }

    private func balance(_ amount: Double) -> some View {
        Text(CurrencyFormatter.string(amount, code: account.isoCurrencyCode))
            .fontWeight(.semibold)
            .monospacedDigit()
    }
}
