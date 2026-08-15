import SwiftUI
import SwiftData

/// A drill-down with data-driven suggestions for where and how to save money.
struct SuggestionsView: View {
    @State private var coordinator = SavingsSuggestionsCoordinator.shared

    private func potentialMonthly(_ suggestions: [SavingsSuggestion]) -> Double {
        suggestions.compactMap(\.monthlyImpact).reduce(0, +)
    }

    var body: some View {
        let suggestions = coordinator.suggestions ?? []
        return ScrollView {
            if coordinator.suggestions == nil {
                ProgressView("Finding ways to save…")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else if suggestions.isEmpty {
                ContentUnavailableView(
                    "No savings ideas yet",
                    systemImage: "checkmark.circle",
                    description: Text("Your current spending does not surface a specific action right now.")
                )
                .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    savingsIntro
                    header(suggestions)
                    Text("Ways to save")
                        .font(.headline)
                        .padding(.top, 4)
                    ForEach(suggestions) { SuggestionCard(suggestion: $0) }
                }
                .padding()
            }
        }
        .navigationTitle("Savings Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SubscriptionsView()
                } label: {
                    Label("Subscriptions", systemImage: "repeat")
                }
            }
        }
    }

    private var savingsIntro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Savings plan")
                .font(.title2.weight(.bold))
            Text("A practical next step for the spending you can see in Insights.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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

struct AskPocketLocketCard: View {
    let entries: [TransactionQuestionContext.Entry]
    let monthlyBudget: Double

    @State private var ai = AIInsightService()
    @State private var question = ""
    @State private var submittedQuestion: String?
    @FocusState private var questionFocused: Bool

    var body: some View {
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

            Text("Ask about your recent transactions. Apple Intelligence processes the answer on-device.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Where did I spend the most?", text: $question, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .focused($questionFocused)
                    .submitLabel(.send)
                    .onSubmit { submitQuestion() }

                Button { submitQuestion() } label: { askButtonLabel }
                    .liquidGlassButtonStyle(.prominent)
                    .disabled(entries.isEmpty || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ai.state == .loading)
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
                    Text("Thinking on-device…").foregroundStyle(.secondary)
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { questionFocused = false }
            }
        }
    }

    @ViewBuilder
    private var askButtonLabel: some View {
        if #available(iOS 26.0, *) {
            Image(systemName: "arrow.up").font(.body.weight(.bold))
        } else {
            Image(systemName: "arrow.up.circle.fill").font(.title2)
        }
    }

    private func markdown(_ string: String) -> AttributedString {
        (try? AttributedString(
            markdown: string,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)
    }

    private func submitQuestion() {
        let submitted = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entries.isEmpty, !submitted.isEmpty, ai.state != .loading else { return }
        question = ""
        questionFocused = false
        submittedQuestion = submitted
        let context = TransactionQuestionContext.make(entries: entries, monthlyBudget: monthlyBudget)
        Task { await ai.ask(question: submitted, transactionContext: context) }
    }
}

struct SavingsQuickWins: View {
    let suggestions: [SavingsSuggestion]
    let action: () -> Void

    private var potentialMonthly: Double {
        suggestions.compactMap(\.monthlyImpact).reduce(0, +)
    }

    var body: some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Ready to save", systemImage: "leaf.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Spacer()
                    Text("~\(CurrencyFormatter.compact(potentialMonthly))/mo")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                }

                ForEach(suggestions.prefix(3)) { suggestion in
                    HStack(spacing: 10) {
                        Image(systemName: suggestion.symbol)
                            .foregroundStyle(suggestion.color)
                            .frame(width: 20)
                        Text(suggestion.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        if let impact = suggestion.monthlyImpact, impact > 0 {
                            Text(CurrencyFormatter.compact(impact))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if suggestion.id != suggestions.prefix(3).last?.id { Divider() }
                }

                Button(action: action) {
                    Label("Open savings plan", systemImage: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
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
