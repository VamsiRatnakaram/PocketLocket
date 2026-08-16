import SwiftUI
import SwiftData

/// Add or edit a manual transaction (cash spending, corrections, or anything a
/// bank/import didn't capture). Manual rows use a `manual-…` id and a synthetic
/// "Cash" account so they flow through the ring, insights, and filters.
struct ManualTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let editing: TransactionRecord?

    @Query private var rules: [CategoryRule]
    @Query private var reimbursementAllocations: [ReimbursementAllocation]

    @State private var amount: Double = 0
    @State private var isExpense = true
    @State private var merchant = ""
    @State private var date = Date()
    @State private var category: SpendCategory = .other
    @State private var didResolveCategory = false
    @State private var errorMessage: String?

    init(editing: TransactionRecord? = nil) {
        self.editing = editing
        if let editing {
            _amount = State(initialValue: abs(editing.amount))
            _isExpense = State(initialValue: editing.amount > 0)
            _merchant = State(initialValue: editing.merchantName ?? editing.name)
            _date = State(initialValue: editing.date)
            // The *resolved* category, not the raw provider one: a per-
            // transaction override or a user rule outranks `categoryPrimary`,
            // so showing the provider's guess here presented a category the
            // user had already corrected.
            // The override outranks `categoryPrimary`, so showing the
            // provider's guess presented a category the user had already
            // corrected. Rules are applied in `.task` below, where the query
            // is available.
            _category = State(initialValue: editing.categoryOverride ?? CategoryMapper.map(primary: editing.categoryPrimary))
        }
    }

    private var isValid: Bool {
        amount > 0
            && !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && allocationConstraintMessage == nil
    }

    private var allocationConstraintMessage: String? {
        guard let editing else { return nil }
        let index = ReimbursementAllocationIndex(reimbursementAllocations)
        let sourced = index.allocatedFromSource(editing.id)
        if sourced > 0.005 {
            guard !isExpense else {
                return "Remove this transaction’s reimbursement allocations before changing it to an expense."
            }
            guard amount + 0.005 >= sourced else {
                return "Amount received must stay at least \(CurrencyFormatter.string(sourced, code: editing.isoCurrencyCode))."
            }
        }
        let reimbursed = index.allocatedToExpense(editing.id)
        if reimbursed > 0.005 {
            guard isExpense else {
                return "Remove this purchase’s reimbursements before changing it to income."
            }
            guard amount + 0.005 >= reimbursed else {
                return "Purchase amount must stay at least \(CurrencyFormatter.string(reimbursed, code: editing.isoCurrencyCode))."
            }
        }
        return nil
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
                } footer: {
                    if let allocationConstraintMessage {
                        Text(allocationConstraintMessage)
                            .foregroundStyle(.red)
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
            .task {
                guard !didResolveCategory, let editing else { return }
                didResolveCategory = true
                category = editing.resolvedCategory(using: rules)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .platformPresentationCornerRadius(30)
            .alert(
                "Couldn’t Save Transaction",
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
            // Writing only `categoryPrimary` left any existing override in
            // place, and the override outranks it — so picking a new category
            // here looked like it did nothing. An explicit choice in this
            // editor is a per-transaction decision, so record it as one.
            editing.categoryOverride = category
        } else {
            let id = "manual-\(UUID().uuidString)"
            context.insert(TransactionRecord(
                id: id, plaidTransactionId: id, name: name, merchantName: name,
                amount: signed, isoCurrencyCode: "USD", date: date, pending: false,
                categoryPrimary: category.plaidPrimary, categoryDetailed: nil,
                logoURL: nil, accountId: "manual-cash"
            ))
        }
        do {
            try ReimbursementAllocationService.reconcile(in: context)
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
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
