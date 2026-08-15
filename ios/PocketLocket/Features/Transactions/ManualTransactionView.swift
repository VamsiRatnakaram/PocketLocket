import SwiftUI
import SwiftData

/// Add or edit a manual transaction (cash spending, corrections, or anything a
/// bank/import didn't capture). Manual rows use a `manual-…` id and a synthetic
/// "Cash" account so they flow through the ring, insights, and filters.
struct ManualTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let editing: TransactionRecord?

    @State private var amount: Double = 0
    @State private var isExpense = true
    @State private var merchant = ""
    @State private var date = Date()
    @State private var category: SpendCategory = .other

    init(editing: TransactionRecord? = nil) {
        self.editing = editing
        if let editing {
            _amount = State(initialValue: abs(editing.amount))
            _isExpense = State(initialValue: editing.amount > 0)
            _merchant = State(initialValue: editing.merchantName ?? editing.name)
            _date = State(initialValue: editing.date)
            _category = State(initialValue: CategoryMapper.map(primary: editing.categoryPrimary))
        }
    }

    private var isValid: Bool {
        amount > 0 && !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $isExpense) {
                        Text("Expense").tag(true)
                        Text("Income").tag(false)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text(isExpense ? "Amount spent" : "Amount received")
                        Spacer()
                        TextField("0", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                }

                Section("Details") {
                    TextField("Merchant or description", text: $merchant)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Category", selection: $category) {
                        ForEach(SpendCategory.allCases) { cat in
                            Label(cat.displayName, systemImage: cat.symbol).tag(cat)
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Add Transaction" : "Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .platformPresentationCornerRadius(30)
        }
    }

    private func save() {
        ensureCashAccount()
        let signed = isExpense ? abs(amount) : -abs(amount)
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)

        if let editing {
            editing.name = name
            editing.merchantName = name
            editing.amount = signed
            editing.date = date
            editing.categoryPrimary = category.plaidPrimary
        } else {
            let id = "manual-\(UUID().uuidString)"
            context.insert(TransactionRecord(
                id: id, plaidTransactionId: id, name: name, merchantName: name,
                amount: signed, isoCurrencyCode: "USD", date: date, pending: false,
                categoryPrimary: category.plaidPrimary, categoryDetailed: nil,
                logoURL: nil, accountId: "manual-cash"
            ))
        }
        try? context.save()
        dismiss()
    }

    private func ensureCashAccount() {
        let exists = ((try? context.fetch(
            FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.plaidAccountId == "manual-cash" })
        ))?.first) != nil
        guard !exists else { return }
        context.insert(AccountRecord(
            id: "manual-cash", plaidAccountId: "manual-cash", name: "Cash",
            officialName: "Cash & Manual", mask: nil, type: "depository", subtype: "cash",
            currentBalance: 0, availableBalance: nil, isoCurrencyCode: "USD"
        ))
    }
}
