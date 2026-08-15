import SwiftUI
import SwiftData

private struct TransactionAssignmentPreparationKey: Equatable {
    let dataHash: Int
    let rulesHash: Int
    let descriptor: String
}

/// Tap a transaction to recategorize it. Choosing a category teaches the app a
/// rule so it auto-categorizes that merchant this way from now on.
struct TransactionDetailView: View {
    let txn: TransactionRecord
    let currentCategory: SpendCategory
    let onGroupingSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var rules: [CategoryRule]
    @Query private var groupingRules: [MerchantGroupingRule]
    @Query private var allTransactions: [TransactionRecord]
    @Query private var accounts: [AccountRecord]
    @Query private var reimbursementAllocations: [ReimbursementAllocation]

    @State private var selected: SpendCategory
    @State private var scope: CategoryAssignment.Scope
    @State private var feedback = 0
    @State private var resolvedMatchKey: String?
    @State private var groupingStats: MerchantAnalytics.MerchantStats?
    @State private var dismissAfterGroupingEdit = false
    @State private var persistedCategory: SpendCategory
    @State private var persistedScope: CategoryAssignment.Scope
    @State private var assignmentErrorMessage: String?
    @State private var originalRuleState: CategoryAssignment.PreparedRuleState?
    @State private var preparedInputKey: TransactionAssignmentPreparationKey?
    @State private var didPersistBroadRule = false
    @State private var pendingRuleStateToRestore: CategoryAssignment.PreparedRuleState?
    @State private var showReimbursementAllocation = false
    /// What the scope picker started on, so dismissing an untouched sheet
    /// writes nothing.
    private let initialScope: CategoryAssignment.Scope

    init(
        txn: TransactionRecord,
        currentCategory: SpendCategory,
        onGroupingSaved: @escaping () -> Void = {}
    ) {
        self.txn = txn
        self.currentCategory = currentCategory
        self.onGroupingSaved = onGroupingSaved
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
        _persistedCategory = State(initialValue: currentCategory)
        _persistedScope = State(initialValue: defaultScope)
    }

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 2 : 4
        return Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: count
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    transferMatchNote
                    reimbursementNote
                    categoryGrid
                }
                .padding(16)
            }
            .navigationTitle("Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sensoryFeedback(.selection, trigger: feedback)
            .task(id: assignmentPreparationKey) {
                prepareAssignment(for: assignmentPreparationKey)
            }
            .alert(
                "Couldn’t Update Category",
                isPresented: Binding(
                    get: { assignmentErrorMessage != nil },
                    set: { if !$0 { assignmentErrorMessage = nil } }
                )
            ) {
                Button("Try Again") {
                    assignmentErrorMessage = nil
                    retryCategoryUpdate()
                }
                Button("Cancel", role: .cancel) { assignmentErrorMessage = nil }
            } message: {
                Text(assignmentErrorMessage ?? "Please try again.")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .platformPresentationCornerRadius(30)
        .onDisappear { persistBeforeDismissal() }
        .sheet(item: $groupingStats, onDismiss: {
            if dismissAfterGroupingEdit {
                onGroupingSaved()
                dismiss()
            }
        }) { stats in
            MerchantGroupingEditorView(stats: stats) {
                dismissAfterGroupingEdit = true
            }
        }
        .sheet(isPresented: $showReimbursementAllocation) {
            if txn.amount < 0 {
                ReimbursementAllocationView(source: txn)
            } else {
                ReimbursementAllocationView(expense: txn)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(selected.tint.opacity(0.18))
                    .frame(width: 52, height: 52)
                Image(systemName: selected.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(selected.tint)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: selected)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(txn.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(txn.date, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(amountText)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(txn.amount > 0 ? Color.primary : Color.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.16), value: selected)
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
        if selected == .transfer {
            return "Kept out of your budget so it doesn't double up with the purchases it covers."
        }
        if selected.isSpending {
            return "You've categorized it as \(selected.displayName), so it still counts toward your budget."
        }
        return "You've categorized it as \(selected.displayName), so it stays out of your budget."
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

    @ViewBuilder
    private var reimbursementNote: some View {
        let index = ReimbursementAllocationIndex(reimbursementAllocations)
        if txn.amount < 0, txn.transferPairId == nil {
            let applied = index.allocatedFromSource(txn.id)
            let remaining = index.remainingSourceAmount(
                transactionID: txn.id,
                originalAmount: txn.amount
            )
            VStack(alignment: .leading, spacing: 10) {
                Label("Reimbursement", systemImage: "person.2.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text(applied > 0
                    ? "\(CurrencyFormatter.string(applied, code: txn.isoCurrencyCode)) applied • "
                        + "\(CurrencyFormatter.string(remaining, code: txn.isoCurrencyCode)) remaining"
                    : "Apply money friends paid back to the purchases it covered.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button { showReimbursementAllocation = true } label: {
                    Label(applied > 0 ? "Review Allocations" : "Apply to Purchases", systemImage: "arrow.triangle.branch")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        } else if txn.amount > 0 {
            let reimbursed = index.allocatedToExpense(txn.id)
            if selected.isSpending || reimbursed > 0.005 {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        reimbursed > 0.005
                            ? (reimbursed >= txn.amount - 0.005 ? "Fully reimbursed" : "Partly reimbursed")
                            : "Reimbursement",
                        systemImage: "person.2.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(.green)
                    Text(reimbursed > 0.005
                        ? "\(CurrencyFormatter.string(reimbursed, code: txn.isoCurrencyCode)) paid back • "
                            + "\(CurrencyFormatter.string(max(0, txn.amount - reimbursed), code: txn.isoCurrencyCode)) net spending"
                        : "Assign incoming payments from friends directly to this purchase.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button { showReimbursementAllocation = true } label: {
                        Label(
                            reimbursed > 0.005 ? "Review Reimbursements" : "Assign Reimbursement",
                            systemImage: "arrow.triangle.branch"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Category").font(.headline)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(SpendCategory.allCases) { category in
                    Button { choose(category) } label: {
                        CategoryChip(category: category, isSelected: category == selected)
                    }
                    .liquidGlassPressableButtonStyle()
                }
            }
            .liquidGlassContainer(spacing: 8)
            scopePicker
            Button { editGrouping() } label: {
                Label("Edit Merchant Grouping", systemImage: "rectangle.3.group")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
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
            .onChange(of: scope) { _, _ in persistSelection() }

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

    private var assignmentPreparationKey: TransactionAssignmentPreparationKey {
        TransactionAssignmentPreparationKey(
            dataHash: RecordHash.transactions(allTransactions),
            rulesHash: RecordHash.rules(rules),
            descriptor: "\(txn.merchantName ?? "")\u{1F}\(txn.name)"
        )
    }

    private var amountText: String {
        let magnitude = CurrencyFormatter.string(abs(txn.amount), code: txn.isoCurrencyCode)
        return txn.amount > 0 ? "-\(magnitude)" : "+\(magnitude)"
    }

    private func choose(_ category: SpendCategory) {
        guard selected != category else { return }
        selected = category
        feedback += 1
        persistSelection()
    }

    /// Calculated only when requested. Building every merchant group requires a
    /// ledger pass, so doing this in `body` would repeat it on each category tap.
    private func editGrouping() {
        let groupingSpecs = groupingRules.map(MerchantGroupingRuleSpec.init(rule:))
        let inputs = allTransactions.map { transaction in
            MerchantAnalytics.Input(
                title: transaction.title,
                amount: transaction.amount,
                category: transaction.resolvedCategory(using: rules),
                date: transaction.date
            )
        }
        groupingStats = MerchantAnalytics
            .merchantStats(inputs, groupingRules: groupingSpecs)
            .first { $0.matches(txn.title) }

        // Income, transfers, and refunds are intentionally absent from Analysis,
        // but their merchant descriptor must still be correctable from here.
        if groupingStats == nil {
            groupingStats = MerchantAnalytics.merchantStats(
                [
                    MerchantAnalytics.Input(
                        title: txn.title,
                        amount: max(abs(txn.amount), 0.01),
                        category: .other,
                        date: txn.date
                    )
                ],
                groupingRules: groupingSpecs
            ).first
        }
    }

    private func prepareAssignment(for inputKey: TransactionAssignmentPreparationKey) {
        guard inputKey == assignmentPreparationKey else { return }
        let matchKey = CategoryAssignment.matchKey(for: txn, in: allTransactions)
        do {
            let original: CategoryAssignment.PreparedRuleState
            if resolvedMatchKey == matchKey, let originalRuleState {
                original = originalRuleState
            } else {
                original = try CategoryAssignment.preparedRuleState(
                    for: matchKey,
                    using: rules,
                    in: context
                )
            }

            if resolvedMatchKey != matchKey,
               didPersistBroadRule,
               pendingRuleStateToRestore == nil {
                pendingRuleStateToRestore = originalRuleState
            }

            originalRuleState = original
            resolvedMatchKey = matchKey
            preparedInputKey = inputKey
            persistSelection(force: pendingRuleStateToRestore != nil)
        } catch {
            assignmentErrorMessage = error.localizedDescription
        }
    }

    private func persistBeforeDismissal() {
        let currentInputKey = assignmentPreparationKey
        if preparedInputKey != currentInputKey {
            prepareAssignment(for: currentInputKey)
        } else {
            persistSelection()
        }
    }

    private func retryCategoryUpdate() {
        let currentInputKey = assignmentPreparationKey
        if preparedInputKey != currentInputKey {
            prepareAssignment(for: currentInputKey)
        } else {
            persistSelection(force: pendingRuleStateToRestore != nil)
        }
    }

    private func persistSelection(force: Bool = false) {
        // Only write when the user actually interacted. The normal path runs
        // on the tap; onDisappear is only a safety net for a change made while
        // the merchant key was still preparing.
        let changedCategory = selected != persistedCategory
        let changedScope = scope != persistedScope
        guard force
                || pendingRuleStateToRestore != nil
                || changedCategory
                || changedScope
        else { return }
        if scope == .allMatching
            && (
                resolvedMatchKey == nil
                    || originalRuleState == nil
                    || preparedInputKey != assignmentPreparationKey
            ) { return }

        do {
            try CategoryAssignment.assign(
                selected,
                to: txn,
                using: rules,
                in: context,
                scope: scope,
                preparedMatchKey: resolvedMatchKey,
                originalRuleState: originalRuleState,
                restoringRuleState: pendingRuleStateToRestore
            )
            persistedCategory = selected
            persistedScope = scope
            didPersistBroadRule = scope == .allMatching
            pendingRuleStateToRestore = nil
        } catch {
            assignmentErrorMessage = error.localizedDescription
        }
    }
}
