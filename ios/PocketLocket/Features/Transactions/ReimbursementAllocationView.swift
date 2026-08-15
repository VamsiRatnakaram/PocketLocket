import SwiftData
import SwiftUI

struct ReimbursementAllocationView: View {
    private enum Direction {
        case fromSource
        case toExpense
    }

    private let transaction: TransactionRecord
    private let direction: Direction

    init(source: TransactionRecord) {
        transaction = source
        direction = .fromSource
    }

    init(expense: TransactionRecord) {
        transaction = expense
        direction = .toExpense
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \TransactionRecord.date, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
    @Query(sort: \ReimbursementAllocation.createdAt, order: .reverse)
    private var allocations: [ReimbursementAllocation]

    @State private var search = ""
    @State private var selectedCounterparty: TransactionRecord?
    @State private var selectedLinkedTransaction: TransactionRecord?
    @State private var amountText = ""
    @State private var errorMessage: String?

    private var index: ReimbursementAllocationIndex {
        ReimbursementAllocationIndex(allocations)
    }

    private var focusedAllocations: [ReimbursementAllocation] {
        switch direction {
        case .fromSource:
            allocations.filter { $0.sourceTransactionID == transaction.id }
        case .toExpense:
            allocations.filter { $0.expenseTransactionID == transaction.id }
        }
    }

    private var allocatedAmount: Double {
        switch direction {
        case .fromSource: index.allocatedFromSource(transaction.id)
        case .toExpense: index.allocatedToExpense(transaction.id)
        }
    }

    private var remainingAmount: Double {
        switch direction {
        case .fromSource:
            index.remainingSourceAmount(
                transactionID: transaction.id,
                originalAmount: transaction.amount
            )
        case .toExpense:
            index.remainingExpenseAmount(
                transactionID: transaction.id,
                originalAmount: transaction.amount
            )
        }
    }

    private var candidates: [TransactionRecord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let unfiltered: [TransactionRecord]
        switch direction {
        case .fromSource:
            unfiltered = ReimbursementCandidateBuilder.candidates(
                for: transaction,
                in: transactions,
                index: index,
                categoryFor: { $0.resolvedCategory(using: rules) }
            )
        case .toExpense:
            unfiltered = ReimbursementSourceCandidateBuilder.candidates(
                for: transaction,
                in: transactions,
                index: index
            )
        }
        return unfiltered.filter {
            query.isEmpty
                || $0.title.localizedCaseInsensitiveContains(query)
                || $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summary
                } footer: {
                    Text("Applied amounts reduce spending on each purchase’s original date and category. The bank transactions stay unchanged.")
                }

                if !focusedAllocations.isEmpty {
                    Section(direction == .fromSource ? "Applied to" : "Reimbursements") {
                        ForEach(focusedAllocations) { allocation in
                            Button { openLinkedTransaction(for: allocation) } label: {
                                allocationRow(allocation)
                            }
                            .buttonStyle(.plain)
                            .disabled(linkedTransaction(for: allocation) == nil)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        remove(allocation)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }

                Section(direction == .fromSource ? "Choose purchases" : "Choose reimbursements") {
                    if remainingAmount <= 0.005 {
                        ContentUnavailableView(
                            direction == .fromSource ? "Fully allocated" : "Fully reimbursed",
                            systemImage: "checkmark.circle",
                            description: Text("Remove an allocation to assign this money elsewhere.")
                        )
                    } else if candidates.isEmpty {
                        ContentUnavailableView(
                            direction == .fromSource ? "No matching purchases" : "No available reimbursements",
                            systemImage: direction == .fromSource ? "receipt" : "person.2",
                            description: Text(direction == .fromSource
                                ? "Try another search or check the transaction currency and category."
                                : "Incoming payments appear here when they have money left to apply.")
                        )
                    } else {
                        ForEach(candidates) { candidate in
                            Button { prepareAllocation(with: candidate) } label: {
                                candidateRow(candidate)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(direction == .fromSource ? "Apply Reimbursement" : "Assign Reimbursement")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $search,
                prompt: direction == .fromSource ? "Search purchases" : "Search incoming payments"
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Amount to Apply", isPresented: allocationAlertIsPresented) {
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) { selectedCounterparty = nil }
                Button("Apply") { applyPreparedAllocation() }
            } message: {
                if let selectedCounterparty {
                    Text(allocationPrompt(for: selectedCounterparty))
                }
            }
            .alert("Couldn’t Apply Reimbursement", isPresented: errorAlertIsPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
            .sheet(item: $selectedLinkedTransaction) { linked in
                TransactionDetailView(
                    txn: linked,
                    currentCategory: linked.resolvedCategory(using: rules)
                )
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(transaction.title)
                .font(.headline)
            HStack {
                switch direction {
                case .fromSource:
                    metric("Received", abs(transaction.amount))
                    metric("Applied", allocatedAmount)
                    metric("Remaining", remainingAmount)
                case .toExpense:
                    metric("Purchase", transaction.amount)
                    metric("Reimbursed", allocatedAmount)
                    metric("Net", remainingAmount)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func metric(_ title: String, _ amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(CurrencyFormatter.string(amount, code: transaction.isoCurrencyCode))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func allocationRow(_ allocation: ReimbursementAllocation) -> some View {
        let linked = linkedTransaction(for: allocation)
        return HStack(spacing: 12) {
            Image(systemName: "arrow.turn.down.right")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(linked?.title ?? "Missing transaction")
                if let linked {
                    Text(linked.date, format: .dateTime.month().day().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(CurrencyFormatter.string(allocation.amount, code: transaction.isoCurrencyCode))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            if linked != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func candidateRow(_ candidate: TransactionRecord) -> some View {
        switch direction {
        case .fromSource:
            expenseCandidateRow(candidate)
        case .toExpense:
            sourceCandidateRow(candidate)
        }
    }

    private func expenseCandidateRow(_ expense: TransactionRecord) -> some View {
        let category = expense.resolvedCategory(using: rules)
        let remaining = index.remainingExpenseAmount(
            transactionID: expense.id,
            originalAmount: expense.amount
        )
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(category.tint.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: category.symbol)
                    .foregroundStyle(category.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title).lineLimit(1)
                Text(expense.date, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.string(expense.amount, code: expense.isoCurrencyCode))
                    .monospacedDigit()
                if remaining < expense.amount - 0.005 {
                    Text("\(CurrencyFormatter.string(remaining, code: expense.isoCurrencyCode)) left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func sourceCandidateRow(_ source: TransactionRecord) -> some View {
        let remaining = index.remainingSourceAmount(
            transactionID: source.id,
            originalAmount: source.amount
        )
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "person.2.fill")
                    .foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(source.title).lineLimit(1)
                Text(source.date, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.string(abs(source.amount), code: source.isoCurrencyCode))
                    .monospacedDigit()
                if remaining < abs(source.amount) - 0.005 {
                    Text("\(CurrencyFormatter.string(remaining, code: source.isoCurrencyCode)) left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var allocationAlertIsPresented: Binding<Bool> {
        Binding(
            get: { selectedCounterparty != nil },
            set: { if !$0 { selectedCounterparty = nil } }
        )
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func prepareAllocation(with counterparty: TransactionRecord) {
        let counterpartyRemaining: Double
        switch direction {
        case .fromSource:
            counterpartyRemaining = index.remainingExpenseAmount(
                transactionID: counterparty.id,
                originalAmount: counterparty.amount
            )
        case .toExpense:
            counterpartyRemaining = index.remainingSourceAmount(
                transactionID: counterparty.id,
                originalAmount: counterparty.amount
            )
        }
        let maximum = min(remainingAmount, counterpartyRemaining)
        amountText = String(format: "%.2f", maximum)
        selectedCounterparty = counterparty
    }

    private func applyPreparedAllocation() {
        guard let counterparty = selectedCounterparty else { return }
        defer { selectedCounterparty = nil }
        let normalized = amountText.replacingOccurrences(of: ",", with: "")
        guard let amount = Double(normalized) else {
            errorMessage = "Enter a valid amount."
            return
        }
        do {
            let source = direction == .fromSource ? transaction : counterparty
            let expense = direction == .fromSource ? counterparty : transaction
            try ReimbursementAllocationService.allocate(
                amount: amount,
                from: source,
                to: expense,
                existing: allocations,
                in: context
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func allocationPrompt(for counterparty: TransactionRecord) -> String {
        let source = direction == .fromSource ? transaction : counterparty
        let expense = direction == .fromSource ? counterparty : transaction
        return "Apply part of \(source.title) to \(expense.title)."
    }

    private func linkedTransaction(
        for allocation: ReimbursementAllocation
    ) -> TransactionRecord? {
        let linkedID = direction == .fromSource
            ? allocation.expenseTransactionID
            : allocation.sourceTransactionID
        return transactions.first { $0.id == linkedID }
    }

    private func openLinkedTransaction(for allocation: ReimbursementAllocation) {
        selectedLinkedTransaction = linkedTransaction(for: allocation)
    }

    private func remove(_ allocation: ReimbursementAllocation) {
        do {
            try ReimbursementAllocationService.remove(allocation, from: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}