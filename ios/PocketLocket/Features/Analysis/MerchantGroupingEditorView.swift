import SwiftUI
import SwiftData

private struct MerchantDescriptorOption: Identifiable {
    let key: String
    let count: Int
    let example: String
    var id: String { key }
}

/// Lets the user override fuzzy merchant grouping with exact descriptor rules.
///
/// Every selected source key is assigned to the same display name. Removing a
/// source that currently belongs to the group writes an explicit self-rule, so
/// the automatic heuristic cannot immediately merge it back in.
struct MerchantGroupingEditorView: View {
    let stats: MerchantAnalytics.MerchantStats
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \TransactionRecord.date, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var categoryRules: [CategoryRule]
    @Query(sort: \MerchantGroupingRule.sourceKey) private var rules: [MerchantGroupingRule]

    @State private var groupName: String
    @State private var selectedSources: Set<String> = []
    @State private var search = ""
    @State private var initialized = false
    @State private var errorMessage: String?
    @State private var descriptorOptions: [MerchantDescriptorOption] = []
    @State private var originalSources: Set<String> = []

    init(stats: MerchantAnalytics.MerchantStats, onSaved: @escaping () -> Void) {
        self.stats = stats
        self.onSaved = onSaved
        _groupName = State(initialValue: stats.name)
    }

    private var options: [MerchantDescriptorOption] {
        descriptorOptions
            .filter {
                search.isEmpty
                    || $0.key.localizedCaseInsensitiveContains(search)
                    || $0.example.localizedCaseInsensitiveContains(search)
            }
            .sorted { left, right in
                let leftSelected = selectedSources.contains(left.key)
                let rightSelected = selectedSources.contains(right.key)
                if leftSelected != rightSelected { return leftSelected }
                return left.key.localizedStandardCompare(right.key) == .orderedAscending
            }
    }

    private var cleanedGroupName: String {
        MerchantGroupingRule.cleanedGroupName(groupName, fallback: "")
    }

    private var existingGroupSources: Set<String> {
        guard let groupID = stats.userGroupingRuleID else { return [] }
        return Set(rules.lazy.filter { $0.groupID == groupID }.map(\.sourceKey))
    }

    private var hasOverrides: Bool {
        let affected = originalSources.isEmpty
            ? stats.aliases.union(existingGroupSources)
            : originalSources
        return rules.contains { affected.contains($0.sourceKey) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Merchant name", text: $groupName)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Group name")
                } footer: {
                    Text("This is the name Analysis will display.")
                }

                Section {
                    ForEach(options) { option in
                        Toggle(isOn: selectionBinding(for: option.key)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.key)
                                    .lineLimit(1)
                                Text("\(option.count) transaction\(option.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(.accentColor)
                    }
                } header: {
                    Text("Included descriptors (\(selectedSources.count))")
                } footer: {
                    Text("Only exact normalized descriptors are changed. Select variants that are the same merchant; deselecting one from this group keeps it separate.")
                }

                if hasOverrides {
                    Section {
                        Button("Use Automatic Grouping", role: .destructive) {
                            resetToAutomatic()
                        }
                    } footer: {
                        Text("Removes your corrections for this group and lets PocketLocket infer it again.")
                    }
                }
            }
            .searchable(text: $search, prompt: "Find another descriptor")
            .navigationTitle("Edit Grouping")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(cleanedGroupName.isEmpty || selectedSources.isEmpty)
                }
            }
            .onAppear { initializeSelectionIfNeeded() }
            .alert(
                "Couldn’t Save Grouping",
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

    private func selectionBinding(for source: String) -> Binding<Bool> {
        Binding(
            get: { selectedSources.contains(source) },
            set: { selected in
                if selected {
                    selectedSources.insert(source)
                } else {
                    selectedSources.remove(source)
                }
            }
        )
    }

    private func initializeSelectionIfNeeded() {
        guard !initialized else { return }
        initialized = true
        let groupingSpecs = rules.map(MerchantGroupingRuleSpec.init(rule:))
        let allStats = MerchantAnalytics.merchantStats(
            transactions.map { transaction in
                MerchantAnalytics.Input(
                    title: transaction.title,
                    amount: transaction.amount,
                    category: transaction.resolvedCategory(using: categoryRules),
                    date: transaction.date
                )
            },
            groupingRules: groupingSpecs
        )
        let fullLedgerAliases = allStats.first {
            $0.id == stats.id || !$0.aliases.isDisjoint(with: stats.aliases)
        }?.aliases ?? stats.aliases
        originalSources = fullLedgerAliases.union(existingGroupSources)
        selectedSources = originalSources
        descriptorOptions = Dictionary(
            grouping: transactions,
            by: { MerchantNormalizer.groupingKey($0.title) }
        ).map { key, matches in
            MerchantDescriptorOption(
                key: key,
                count: matches.count,
                example: matches.first?.title ?? key
            )
        }
    }

    private func save() {
        do {
            try MerchantGroupingAssignment.apply(
                groupName: cleanedGroupName,
                selectedSources: selectedSources,
                originalSources: originalSources,
                rules: rules,
                in: context
            )
            finishSave()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetToAutomatic() {
        do {
            try MerchantGroupingAssignment.reset(
                sources: originalSources,
                rules: rules,
                in: context
            )
            finishSave()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finishSave() {
        onSaved()
        dismiss()
    }
}
