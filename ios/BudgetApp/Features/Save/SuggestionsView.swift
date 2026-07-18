import SwiftUI
import SwiftData

/// The "Save" tab — data-driven suggestions for where and how to save money.
struct SuggestionsView: View {
    @Query(sort: \TransactionRecord.date, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
    @AppStorage("monthlyBudget") private var monthlyBudget: Double = 3000
    @AppStorage(SpendingAccountFilter.key) private var excludedAccountsRaw = ""
    @State private var ai = AIInsightService()

    private var monthTransactions: [TransactionRecord] {
        let interval = Calendar.current.dateInterval(of: .month, for: Date())
            ?? DateInterval(start: .distantPast, duration: 0)
        let excluded = SpendingAccountFilter.excludedIds(from: excludedAccountsRaw)
        return transactions.filter {
            interval.contains($0.date) && SpendingAccountFilter.isIncluded($0.accountId, excluded: excluded)
        }
    }

    private var previousMonthTransactions: [TransactionRecord] {
        let calendar = Calendar.current
        guard
            let lastMonth = calendar.date(byAdding: .month, value: -1, to: Date()),
            let interval = calendar.dateInterval(of: .month, for: lastMonth)
        else { return [] }
        let excluded = SpendingAccountFilter.excludedIds(from: excludedAccountsRaw)
        return transactions.filter {
            interval.contains($0.date) && SpendingAccountFilter.isIncluded($0.accountId, excluded: excluded)
        }
    }

    private func inputs(_ txns: [TransactionRecord]) -> [SavingsAdvisor.Input] {
        txns.map { txn in
            let haystack = (txn.merchantName ?? "") + " " + txn.name
            return SavingsAdvisor.Input(
                title: txn.title,
                amount: txn.amount,
                category: txn.resolvedCategory(using: rules),
                isSubscription: MerchantHeuristics.isLikelySubscription(haystack)
            )
        }
    }

    private var suggestions: [SavingsSuggestion] {
        SavingsAdvisor.suggestions(
            inputs(monthTransactions),
            previous: inputs(previousMonthTransactions),
            monthlyBudget: monthlyBudget
        )
    }

    private var potentialMonthly: Double {
        suggestions.compactMap(\.monthlyImpact).reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if suggestions.isEmpty {
                    ContentUnavailableView(
                        "No suggestions yet",
                        systemImage: "sparkles",
                        description: Text("Connect an account or import a statement to get personalized ways to save.")
                    )
                    .padding(.top, 60)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        aiCard
                        Text("Ways to save")
                            .font(.headline)
                            .padding(.top, 4)
                        ForEach(suggestions) { SuggestionCard(suggestion: $0) }
                    }
                    .padding()
                }
            }
            .navigationTitle("Save")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SubscriptionsView()
                    } label: {
                        Label("Subscriptions", systemImage: "repeat")
                    }
                }
            }
            .task(id: aiSignature) {
                guard !suggestions.isEmpty else { return }
                await ai.generateIfNeeded(prompt: aiPrompt, signature: aiSignature)
            }
        }
    }

    @ViewBuilder private var aiCard: some View {
        switch ai.state {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Thinking on-device…").foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        case let .ready(text):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .symbolRenderingMode(.multicolor)
                    Text("Apple Intelligence")
                        .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                    Spacer()
                    Button {
                        Task { await ai.regenerate(prompt: aiPrompt, signature: aiSignature) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.semibold))

                Text(markdown(text))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(
                        colors: [.purple.opacity(0.14), .blue.opacity(0.10)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.purple.opacity(0.5), .blue.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
        case .idle, .unavailable:
            EmptyView()
        }
    }

    private var aiPrompt: String {
        let lines = suggestions.map { "- \($0.title): \($0.detail)" }.joined(separator: "\n")
        return """
        Monthly budget: \(CurrencyFormatter.string(monthlyBudget)).
        Observations from this month:
        \(lines)
        Give me a couple of specific, encouraging ways to save money.
        """
    }

    private func markdown(_ string: String) -> AttributedString {
        (try? AttributedString(
            markdown: string,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)
    }

    private var aiSignature: String {
        let parts = suggestions.map { "\($0.title)|\(Int(($0.monthlyImpact ?? 0).rounded()))" }
        return (["budget:\(Int(monthlyBudget))"] + parts).joined(separator: ";")
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "leaf.fill")
                .font(.title3)
                .foregroundStyle(.green)
            Text("Potential savings")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(CurrencyFormatter.string(potentialMonthly))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(
                    LinearGradient(colors: [.green, .teal], startPoint: .leading, endPoint: .trailing)
                )
            Text("per month if you act on these ideas")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

struct SuggestionCard: View {
    let suggestion: SavingsSuggestion

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(suggestion.tint.opacity(0.18)).frame(width: 44, height: 44)
                Image(systemName: suggestion.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(suggestion.tint)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(suggestion.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if let impact = suggestion.monthlyImpact, impact > 0 {
                        Text("~\(CurrencyFormatter.compact(impact))/mo")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(suggestion.tint.opacity(0.18), in: Capsule())
                            .foregroundStyle(suggestion.tint)
                            .fixedSize()
                    }
                }
                Text(suggestion.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
