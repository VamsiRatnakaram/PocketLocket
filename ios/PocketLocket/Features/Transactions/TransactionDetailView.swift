import SwiftUI
import SwiftData

/// Tap a transaction to recategorize it. Choosing a category teaches the app a
/// rule so it auto-categorizes that merchant this way from now on.
struct TransactionDetailView: View {
    let txn: TransactionRecord
    let currentCategory: SpendCategory

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var rules: [CategoryRule]
    @Query private var allTransactions: [TransactionRecord]
    @Query private var accounts: [AccountRecord]

    @State private var selected: SpendCategory
    @State private var feedback = 0

    init(txn: TransactionRecord, currentCategory: SpendCategory) {
        self.txn = txn
        self.currentCategory = currentCategory
        _selected = State(initialValue: currentCategory)
    }

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    transferMatchNote
                    categoryGrid
                }
                .padding()
            }
            .navigationTitle("Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sensoryFeedback(.selection, trigger: feedback)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .onDisappear { persistSelection() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(selected.tint.opacity(0.18)).frame(width: 68, height: 68)
                Image(systemName: selected.symbol)
                    .font(.title)
                    .foregroundStyle(selected.tint)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: selected)
            }
            Text(txn.title).font(.title3.bold())
            Text(txn.date, format: .dateTime.month().day().year())
                .font(.subheadline).foregroundStyle(.secondary)
            Text(amountText)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(txn.amount > 0 ? Color.primary : Color.green)
        }
    }

    /// Explains *why* this was treated as a transfer. A matched pair is a claim
    /// about the user's own money moving between their accounts, so it should
    /// name its evidence rather than silently removing the transaction from the
    /// budget.
    /// The match only keeps a transaction out of the budget while nothing the
    /// user chose outranks it. Saying "kept out of your budget" unconditionally
    /// contradicted the category shown right above it once a rule or a
    /// per-transaction override put the money back into spending.
    private var transferBudgetNote: String {
        currentCategory == .transfer
            ? "Kept out of your budget so it doesn't double up with the purchases it covers."
            : "You've categorized it as \(currentCategory.displayName), so it still counts toward your budget."
    }

    @ViewBuilder
    private var transferMatchNote: some View {
        if let counterpart {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Matched transfer")
                        .font(.subheadline.weight(.semibold))
                    Text("A matching \(CurrencyFormatter.string(abs(counterpart.amount), code: counterpart.isoCurrencyCode)) "
                        + "\(txn.amount > 0 ? "credit" : "payment") \(counterpartAccountName) "
                        + "on \(counterpart.date.formatted(.dateTime.month().day())). "
                        + transferBudgetNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var counterpart: TransactionRecord? {
        guard let pairId = txn.transferPairId else { return nil }
        return allTransactions.first { $0.transferPairId == pairId && $0.id != txn.id }
    }

    private var counterpartAccountName: String {
        guard let accountId = counterpart?.accountId,
              let account = accounts.first(where: { $0.id == accountId })
        else { return "on another account" }
        return "on \(account.displayName)"
    }

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category").font(.headline)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(SpendCategory.allCases) { category in
                    Button { choose(category) } label: {
                        CategoryChip(category: category, isSelected: category == selected)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            Text("Choosing a category teaches the app to auto-categorize “\(matchKey)” this way from now on.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var matchKey: String {
        CategoryAssignment.matchKey(for: txn)
    }

    private var amountText: String {
        let magnitude = CurrencyFormatter.string(abs(txn.amount), code: txn.isoCurrencyCode)
        return txn.amount > 0 ? "-\(magnitude)" : "+\(magnitude)"
    }

    private func choose(_ category: SpendCategory) {
        withAnimation(.snappy) { selected = category }
        feedback += 1
    }

    private func persistSelection() {
        guard selected != currentCategory else { return }
        try? CategoryAssignment.assign(selected, to: [txn], using: rules, in: context)
    }
}
