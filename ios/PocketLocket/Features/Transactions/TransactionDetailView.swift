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
    @State private var scope: CategoryAssignment.Scope
    @State private var feedback = 0
    @State private var resolvedMatchKey: String?
    /// What the scope picker started on, so dismissing an untouched sheet
    /// writes nothing.
    private let initialScope: CategoryAssignment.Scope

    init(txn: TransactionRecord, currentCategory: SpendCategory) {
        self.txn = txn
        self.currentCategory = currentCategory
        _selected = State(initialValue: currentCategory)
        let descriptor = (txn.merchantName ?? "") + " " + txn.name
        let defaultScope: CategoryAssignment.Scope
        if txn.categoryOverride != nil {
            // Reopening a transaction the user already scoped to itself has to
            // show that choice. Defaulting back to "All like this" meant
            // changing the category a second time silently widened it into a
            // merchant-wide rule the user never asked for.
            defaultScope = .thisTransactionOnly
        } else {
            defaultScope = MerchantHeuristics.isPeerToPeer(descriptor) ? .thisTransactionOnly : .allMatching
        }
        self.initialScope = defaultScope
        _scope = State(initialValue: defaultScope)
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
            .task {
                resolvedMatchKey = CategoryAssignment.matchKey(for: txn, in: allTransactions)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .platformPresentationCornerRadius(30)
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
                    .liquidGlassPressableButtonStyle()
                }
            }
            .liquidGlassContainer(spacing: 8)
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
            // Segment labels stay short and fixed. Interpolating the merchant
            // name here overflowed the segment -- descriptors are routinely
            // long ("SQ *BLUE BOTTLE COFFEE SAN FRANCISCO CA"), and a
            // segmented control can't wrap or scroll. The name lives in the
            // caption below instead, which wraps to as many lines as it needs.
            Picker("Apply to", selection: $scope) {
                Text("Just this one").tag(CategoryAssignment.Scope.thisTransactionOnly)
                Text("All like this").tag(CategoryAssignment.Scope.allMatching)
            }
            .pickerStyle(.segmented)

            Text(scopeExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var scopeExplanation: String {
        switch scope {
        case .thisTransactionOnly:
            return "Only this transaction changes. Everything else from “\(matchKeyDisplay)” is left alone."
        case .allMatching:
            return "Teaches the app to auto-categorize “\(matchKeyDisplay)” this way from now on, including future transactions."
        }
    }

    /// Bank descriptors can run very long. Truncate for display so the caption
    /// stays a readable sentence rather than a wall of text — the full value is
    /// still what gets matched on.
    private var matchKeyDisplay: String {
        let limit = 34
        guard matchKey.count > limit else { return matchKey }
        return matchKey.prefix(limit).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Resolved once rather than per render: folding the ledger's descriptors
    /// into merchant identities is far too much work for a computed property
    /// SwiftUI re-evaluates on every state change.
    private var matchKey: String {
        resolvedMatchKey ?? CategoryAssignment.matchKey(for: txn)
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
        try? CategoryAssignment.assign(
            selected, to: [txn], using: rules, in: context, scope: scope, ledger: allTransactions
        )
    }
}
