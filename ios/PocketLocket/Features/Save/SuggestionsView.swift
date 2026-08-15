import SwiftUI
import SwiftData

/// The "Save" tab — data-driven suggestions for where and how to save money.
struct SuggestionsView: View {
    var isActive = true

    @AppStorage("monthlyBudget") private var monthlyBudget: Double = 3000
    @AppStorage(SpendingAccountFilter.key) private var excludedAccountsRaw = ""
    @State private var ai = AIInsightService()
    @State private var question = ""
    @State private var submittedQuestion: String?
    @State private var questionEntries: [TransactionQuestionContext.Entry]?
    @State private var isVisible = false
    @FocusState private var questionFocused: Bool
    @State private var coordinator = SavingsSuggestionsCoordinator.shared

    private func potentialMonthly(_ suggestions: [SavingsSuggestion]) -> Double {
        suggestions.compactMap(\.monthlyImpact).reduce(0, +)
    }

    /// Day precision keeps the dynamic SwiftData query identical across normal
    /// body renders (including every keystroke) while still advancing daily.
    private var transactionCutoff: Date {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .month, value: -12, to: Date()) ?? .distantPast
        return calendar.startOfDay(for: date)
    }

    var body: some View {
        let suggestions = coordinator.suggestions ?? []
        return ScrollView {
                if questionEntries == nil {
                    ProgressView("Loading your transactions…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if questionEntries?.isEmpty == true {
                    ContentUnavailableView(
                        "No suggestions yet",
                        systemImage: "sparkles",
                        description: Text("Connect an account or import a statement to get personalized ways to save.")
                    )
                    .padding(.top, 60)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        if !suggestions.isEmpty { header(suggestions) }
                        aiCard
                        if coordinator.suggestions == nil {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Finding ways to save…")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        }
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
            // Keep the UI mounted for scroll/question state, but only keep the
            // query-owning driver alive while Save is visible.
            .background {
                if isActive && isVisible {
                    SavingsSuggestionsDataDriver(
                        monthlyBudget: monthlyBudget,
                        excludedAccountsRaw: excludedAccountsRaw,
                        transactionCutoff: transactionCutoff,
                        questionEntries: $questionEntries,
                        coordinator: coordinator
                    )
                }
            }
            .onAppear { isVisible = true }
            .onDisappear {
                isVisible = false
                questionFocused = false
                coordinator.suspend()
            }
            .onChange(of: isActive) { _, active in
                if !active {
                    questionFocused = false
                    coordinator.suspend()
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
            entries: questionEntries ?? [],
            monthlyBudget: monthlyBudget
        )
        Task { await ai.ask(question: submitted, transactionContext: context) }
    }

    private func header(_ suggestions: [SavingsSuggestion]) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "leaf.fill")
                .font(.title3)
                .foregroundStyle(.green)
            Text("Potential savings")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(CurrencyFormatter.string(potentialMonthly(suggestions)))
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

/// The Save screen keeps its UI tree mounted for instant segment switches, but
/// its SwiftData subscriptions and request hashing exist only while visible.
private struct SavingsSuggestionsDataDriver: View {
    struct Request: Equatable {
        let suggestions: SavingsSuggestionsCoordinator.Request
        let questionDataHash: Int
    }

    let monthlyBudget: Double
    let excludedAccountsRaw: String
    let transactionCutoff: Date
    @Binding var questionEntries: [TransactionQuestionContext.Entry]?
    let coordinator: SavingsSuggestionsCoordinator

    @Query private var transactions: [TransactionRecord]
    @Query private var rules: [CategoryRule]

    init(
        monthlyBudget: Double,
        excludedAccountsRaw: String,
        transactionCutoff: Date,
        questionEntries: Binding<[TransactionQuestionContext.Entry]?>,
        coordinator: SavingsSuggestionsCoordinator
    ) {
        self.monthlyBudget = monthlyBudget
        self.excludedAccountsRaw = excludedAccountsRaw
        self.transactionCutoff = transactionCutoff
        self._questionEntries = questionEntries
        self.coordinator = coordinator

        _transactions = Query(
            filter: #Predicate<TransactionRecord> { $0.date >= transactionCutoff },
            sort: \TransactionRecord.date,
            order: .reverse
        )
    }

    private var currentMonth: DateInterval {
        Calendar.current.dateInterval(of: .month, for: Date())
            ?? DateInterval(start: .distantPast, duration: 0)
    }

    private var previousMonth: DateInterval {
        let calendar = Calendar.current
        guard
            let lastMonth = calendar.date(byAdding: .month, value: -1, to: Date()),
            let interval = calendar.dateInterval(of: .month, for: lastMonth)
        else { return DateInterval(start: .distantPast, duration: 0) }
        return interval
    }

    private var includedTransactions: [TransactionRecord] {
        let excluded = SpendingAccountFilter.excludedIds(from: excludedAccountsRaw)
        return transactions.filter {
            SpendingAccountFilter.isIncluded($0.accountId, excluded: excluded)
        }
    }

    private var suggestionTransactions: [TransactionRecord] {
        includedTransactions.filter {
            $0.date >= previousMonth.start && $0.date < currentMonth.end
        }
    }

    private var questionTransactions: [TransactionRecord] {
        Array(includedTransactions.lazy.filter { $0.date >= transactionCutoff }.prefix(120))
    }

    private var request: Request {
        let suggestionTransactions = suggestionTransactions
        return Request(
            suggestions: SavingsSuggestionsCoordinator.Request(
                key: SavingsSuggestionsCache.InputsKey(
                    dataHash: RecordHash.transactions(suggestionTransactions),
                    rulesHash: RecordHash.rules(rules),
                    excludedAccountsRaw: excludedAccountsRaw,
                    monthlyBudget: monthlyBudget,
                    monthStart: currentMonth.start
                )
            ),
            questionDataHash: RecordHash.transactions(questionTransactions)
        )
    }

    var body: some View {
        Color.clear
            .onChange(of: request, initial: true) { _, newRequest in
                refresh(newRequest)
            }
            .onDisappear { coordinator.suspend() }
            .accessibilityHidden(true)
    }

    private func refresh(_ request: Request) {
        let rules = rules
        questionEntries = questionTransactions.map { transaction in
            TransactionQuestionContext.Entry(
                date: transaction.date,
                title: transaction.title,
                amount: transaction.amount,
                currency: transaction.isoCurrencyCode,
                category: transaction.resolvedCategory(using: rules).displayName
            )
        }
        coordinator.refresh(
            request.suggestions,
            transactions: suggestionTransactions.map(AnalysisTransaction.init(record:)),
            rules: rules.map(CategoryRuleSpec.init(rule:)),
            currentMonth: currentMonth,
            previousMonth: previousMonth,
            monthlyBudget: monthlyBudget
        )
    }
}

struct SuggestionCard: View {
    let suggestion: SavingsSuggestion

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(suggestion.color.opacity(0.18)).frame(width: 44, height: 44)
                Image(systemName: suggestion.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(suggestion.color)
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
                            .background(suggestion.color.opacity(0.18), in: Capsule())
                            .foregroundStyle(suggestion.color)
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
