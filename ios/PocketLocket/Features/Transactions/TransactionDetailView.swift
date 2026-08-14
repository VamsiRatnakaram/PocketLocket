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

    @State private var selected: SpendCategory
    @State private var scope: CategoryAssignment.Scope
    @State private var feedback = 0
    /// What the scope picker started on, so dismissing an untouched sheet
    /// writes nothing.
    private let initialScope: CategoryAssignment.Scope

    init(txn: TransactionRecord, currentCategory: SpendCategory) {
        self.txn = txn
        self.currentCategory = currentCategory
        _selected = State(initialValue: currentCategory)
        let descriptor = (txn.merchantName ?? "") + " " + txn.name
        let defaultScope: CategoryAssignment.Scope =
            MerchantHeuristics.isPeerToPeer(descriptor) ? .thisTransactionOnly : .allMatching
        self.initialScope = defaultScope
        _scope = State(initialValue: defaultScope)
    }

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
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
            scopePicker
        }
    }

    /// Lets a choice apply to one transaction instead of every transaction from
    /// the same merchant.
    ///
    /// Previously every recategorization taught a merchant-wide rule, so
    /// correcting a single Venmo silently retagged your entire Venmo history.
    /// P2P descriptors are ambiguous per transaction by nature, so they default
    /// to the narrow scope; ordinary merchants keep the old teach-a-rule
    /// behavior, which is what makes the app learn.
    private var scopePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Apply to", selection: $scope) {
                Text("Just this one").tag(CategoryAssignment.Scope.thisTransactionOnly)
                Text("All “\(matchKey)”").tag(CategoryAssignment.Scope.allMatching)
            }
            .pickerStyle(.segmented)

            Text(scopeExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var scopeExplanation: String {
        switch scope {
        case .thisTransactionOnly:
            return "Only this transaction changes. Everything else from “\(matchKey)” is left alone."
        case .allMatching:
            return "Teaches the app to auto-categorize “\(matchKey)” this way from now on, including future transactions."
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
        // Only write when the user actually interacted. Opening a sheet and
        // dismissing it must not pin a category — with the narrow scope that
        // would freeze an auto-categorized transaction against future rule
        // changes.
        let changedCategory = selected != currentCategory
        let changedScope = scope != initialScope
        guard changedCategory || changedScope else { return }
        try? CategoryAssignment.assign(selected, to: [txn], using: rules, in: context, scope: scope)
    }
}
