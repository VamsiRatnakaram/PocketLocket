import SwiftData
import SwiftUI

struct ReimbursementAllocationView: View {
    let source: TransactionRecord

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \TransactionRecord.date, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
    @Query(sort: \ReimbursementAllocation.createdAt, order: .reverse)
    private var allocations: [ReimbursementAllocation]

    @State private var search = ""
    @State private var selectedExpense: TransactionRecord?
    @State private var amountText = ""
    @State private var errorMessage: String?

    private var index: ReimbursementAllocationIndex {
        ReimbursementAllocationIndex(allocations)
    }

    private var sourceAllocations: [ReimbursementAllocation] {
        allocations.filter { $0.sourceTransactionID == source.id }
    }

    private var allocatedAmount: Double {
        index.allocatedFromSource(source.id)
    }

    private var remainingAmount: Double {
        index.remainingSourceAmount(transactionID: source.id, originalAmount: source.amount)
    }

    private var candidates: [TransactionRecord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReimbursementCandidateBuilder.candidates(
            for: source,
            in: transactions,
            index: index,
            categoryFor: { $0.resolvedCategory(using: rules) }
        ).filter {
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

                if !sourceAllocations.isEmpty {
                    Section("Applied to") {
                        ForEach(sourceAllocations) { allocation in
                            allocationRow(allocation)
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

                Section("Choose purchases") {
                    if remainingAmount <= 0.005 {
                        ContentUnavailableView(
                            "Fully allocated",
                            systemImage: "checkmark.circle",
                            description: Text("Remove an allocation to assign this money elsewhere.")
                        )
                    } else if candidates.isEmpty {
                        ContentUnavailableView(
                            "No matching purchases",
                            systemImage: "receipt",
                            description: Text("Try another search or check the transaction currency and category.")
                        )
                    } else {
                        ForEach(candidates) { expense in
                            Button { prepareAllocation(to: expense) } label: {
                                candidateRow(expense)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Apply Reimbursement")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search purchases")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Amount to Apply", isPresented: allocationAlertIsPresented) {
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) { selectedExpense = nil }
                Button("Apply") { applyPreparedAllocation() }
            } message: {
                if let selectedExpense {
                    Text("Apply part of \(source.title) to \(selectedExpense.title).")
                }
            }
            .alert("Couldn’t Apply Reimbursement", isPresented: errorAlertIsPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(source.title)
                .font(.headline)
            HStack {
                metric("Received", abs(source.amount))
                metric("Applied", allocatedAmount)
                metric("Remaining", remainingAmount)
            }
        }
        .padding(.vertical, 4)
    }

    private func metric(_ title: String, _ amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(CurrencyFormatter.string(amount, code: source.isoCurrencyCode))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func allocationRow(_ allocation: ReimbursementAllocation) -> some View {
        let expense = transactions.first { $0.id == allocation.expenseTransactionID }
        return HStack(spacing: 12) {
            Image(systemName: "arrow.turn.down.right")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(expense?.title ?? "Missing purchase")
                if let expense {
                    Text(expense.date, format: .dateTime.month().day().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(CurrencyFormatter.string(allocation.amount, code: source.isoCurrencyCode))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }

    private func candidateRow(_ expense: TransactionRecord) -> some View {
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

    private var allocationAlertIsPresented: Binding<Bool> {
        Binding(
            get: { selectedExpense != nil },
            set: { if !$0 { selectedExpense = nil } }
        )
    }

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func prepareAllocation(to expense: TransactionRecord) {
        let maximum = min(
            remainingAmount,
            index.remainingExpenseAmount(
                transactionID: expense.id,
                originalAmount: expense.amount
            )
        )
        amountText = String(format: "%.2f", maximum)
        selectedExpense = expense
    }

    private func applyPreparedAllocation() {
        guard let expense = selectedExpense else { return }
        defer { selectedExpense = nil }
        let normalized = amountText.replacingOccurrences(of: ",", with: "")
        guard let amount = Double(normalized) else {
            errorMessage = "Enter a valid amount."
            return
        }
        do {
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

    private func remove(_ allocation: ReimbursementAllocation) {
        do {
            try ReimbursementAllocationService.remove(allocation, from: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}