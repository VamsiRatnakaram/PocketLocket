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
    @State private var feedback = 0
    @State private var detent: PresentationDetent = .large

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
        .presentationDetents([.medium, .large], selection: $detent)
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
            Text("Choosing a category teaches the app to auto-categorize “\(matchKey)” this way from now on.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var matchKey: String {
        let descriptor = txn.merchantName ?? txn.name
        let cleaned = MerchantHeuristics.ruleMatchText(for: descriptor)
        return cleaned.isEmpty ? descriptor : cleaned
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
        let key = matchKey.lowercased()
        if let existing = rules.first(where: { $0.matchText == key }) {
            existing.categoryRaw = selected.rawValue
        } else {
            context.insert(CategoryRule(matchText: key, category: selected))
        }
        try? context.save()
    }
}
