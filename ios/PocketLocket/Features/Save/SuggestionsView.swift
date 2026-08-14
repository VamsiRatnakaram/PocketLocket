import SwiftUI
import SwiftData

/// The "Save" tab — data-driven suggestions for where and how to save money.
struct SuggestionsView: View {
    /// Rendered at the top of the scroll content so it scrolls away, rather
    /// than being pinned above this view by the parent.
    var segmentPicker: AnalysisSegmentPicker?

    @Query private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]
    @AppStorage("monthlyBudget") private var monthlyBudget: Double = 3000
    @AppStorage(SpendingAccountFilter.key) private var excludedAccountsRaw = ""
    @State private var ai = AIInsightService()
    @State private var question = ""
    @State private var submittedQuestion: String?
    @FocusState private var questionFocused: Bool

    init(segmentPicker: AnalysisSegmentPicker? = nil) {
        self.segmentPicker = segmentPicker
        let cutoff = Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? .distantPast
        _transactions = Query(
            filter: #Predicate<TransactionRecord> { $0.date >= cutoff },
            sort: \TransactionRecord.date,
            order: .reverse
        )
    }

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

    private var questionTransactions: [TransactionRecord] {
        let cutoff = Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? .distantPast
        let excluded = SpendingAccountFilter.excludedIds(from: excludedAccountsRaw)
        return Array(transactions.lazy.filter {
            $0.date >= cutoff && SpendingAccountFilter.isIncluded($0.accountId, excluded: excluded)
        }.prefix(120))
    }

    private var potentialMonthly: Double {
        suggestions.compactMap(\.monthlyImpact).reduce(0, +)
    }

    var body: some View {
        ScrollView {
                if questionTransactions.isEmpty {
                    VStack(spacing: 0) {
                        segmentPicker
                            .padding(.horizontal)
                        ContentUnavailableView(
                            "No suggestions yet",
                            systemImage: "sparkles",
                            description: Text("Connect an account or import a statement to get personalized ways to save.")
                        )
                        .padding(.top, 60)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        segmentPicker
                        if !suggestions.isEmpty { header }
                        aiCard
                        if !suggestions.isEmpty {
                            Text("Ways to save")
                                .font(.headline)
                                .padding(.top, 4)
                            ForEach(suggestions) { SuggestionCard(suggestion: $0) }
                        }
                    }
                    .padding()
                }
            }
            .scrollDismissesKeyboard(.interactively)
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if questionFocused {
                HStack {
                    Spacer()
                    Button("Done") { questionFocused = false }
                        .fontWeight(.semibold)
                }
                .frame(height: 44)
                .padding(.horizontal)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
            }
        }
    }

    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.multicolor)
                Text("Ask PocketLocket")
                    .font(.headline)
                Text("BETA")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                Spacer()
            }

            Text("Ask about your recent transactions. This beta uses Apple Intelligence on-device, so answers may not always be accurate.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Where did I spend the most?", text: $question, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .focused($questionFocused)
                    .submitLabel(.send)
                    .onSubmit { submitQuestion() }

                Button { submitQuestion() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ai.state == .loading)
                .accessibilityLabel("Ask question")
            }

            if let submittedQuestion {
                Text(submittedQuestion)
                    .font(.subheadline.weight(.medium))
            }

            switch ai.state {
            case .idle:
                EmptyView()
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Thinking on-device…")
                        .foregroundStyle(.secondary)
                }
            case let .ready(text):
                Text(markdown(text))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            case .unavailable:
                Label("Apple Intelligence is not available on this device.", systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .failed:
                Label("The question couldn’t be answered. Please try again.", systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func markdown(_ string: String) -> AttributedString {
        (try? AttributedString(
            markdown: string,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)
    }

    private func submitQuestion() {
        let submitted = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submitted.isEmpty, ai.state != .loading else { return }
        question = ""
        questionFocused = false
        submittedQuestion = submitted
        let context = TransactionQuestionContext.make(
            entries: questionTransactions.map { transaction in
                TransactionQuestionContext.Entry(
                    date: transaction.date,
                    title: transaction.title,
                    amount: transaction.amount,
                    currency: transaction.isoCurrencyCode,
                    category: transaction.resolvedCategory(using: rules).displayName
                )
            },
            monthlyBudget: monthlyBudget
        )
        Task { await ai.ask(question: submitted, transactionContext: context) }
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
