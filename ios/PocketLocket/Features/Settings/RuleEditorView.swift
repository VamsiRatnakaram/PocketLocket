import SwiftUI
import SwiftData

/// Create or edit a single category rule.
///
/// Rules used to be write-once: taught implicitly by recategorizing a
/// transaction, then only deletable. A typo, a merchant that renamed itself, or
/// a rule that turned out to be too broad meant deleting it and hunting down a
/// transaction to teach it again.
struct RuleEditorView: View {
    /// The rule being edited, or `nil` when creating one.
    let rule: CategoryRule?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var transactions: [TransactionRecord]
    @Query private var allRules: [CategoryRule]

    @State private var matchText: String
    @State private var category: SpendCategory
    @State private var errorMessage: String?

    init(rule: CategoryRule?) {
        self.rule = rule
        _matchText = State(initialValue: rule?.matchText ?? "")
        _category = State(initialValue: rule?.category ?? .other)
    }

    private var trimmed: String {
        matchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var matchKey: String {
        CategoryRule.canonicalMatchText(trimmed)
    }

    /// Transactions this rule would claim, so the effect of a wording change is
    /// visible before it is saved rather than discovered afterwards.
    private var matches: [TransactionRecord] {
        guard !trimmed.isEmpty else { return [] }
        // Matched with the same tokenizer the resolver uses, rather than by
        // building a throwaway CategoryRule: that is a SwiftData model, and one
        // created outside a context to preview a match would be a live object
        // waiting to be saved by accident.
        let ruleTokens = MerchantHeuristics.tokens(in: trimmed)
        return transactions.filter {
            let descriptor = MerchantHeuristics.tokens(in: (($0.merchantName ?? "") + " " + $0.name))
            return MerchantHeuristics.contains(ruleTokens, in: descriptor)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Merchant text", text: $matchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Matches when a transaction contains")
                } footer: {
                    Text("Matched on whole words, ignoring case and punctuation, against the merchant and description. \"trader joe\" catches \"TRADER JOE'S #45\".")
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(SpendCategory.allCases) { option in
                            Label(option.displayName, systemImage: option.symbol).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.inline)
                }

                Section {
                    if trimmed.isEmpty {
                        Text("Enter some text to see what it would match.")
                            .foregroundStyle(.secondary)
                    } else if matches.isEmpty {
                        Label("Nothing on this device matches yet", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(matches.prefix(20)) { txn in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(txn.merchantName ?? txn.name).lineLimit(1)
                                Text(txn.date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(matches.isEmpty ? "Preview" : "Matches \(matches.count) transaction\(matches.count == 1 ? "" : "s")")
                } footer: {
                    if matches.count > 20 {
                        Text("Showing the first 20.")
                    }
                }
            }
            .navigationTitle(rule == nil ? "New Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(trimmed.isEmpty)
                }
            }
            .alert(
                "Couldn’t Save Rule",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private func save() {
        // matchText is a unique attribute, so a collision would trap on save
        // rather than surface as an error.
        let clash = allRules.contains {
            CategoryRule.canonicalMatchText($0.matchText) == matchKey
                && $0.persistentModelID != rule?.persistentModelID
        }
        if clash {
            errorMessage = "Another rule already matches “\(trimmed)”. Edit or delete that one instead."
            return
        }

        if let rule {
            rule.matchText = trimmed
            rule.categoryRaw = category.rawValue
        } else {
            context.insert(CategoryRule(matchText: trimmed, category: category))
        }
        do {
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
