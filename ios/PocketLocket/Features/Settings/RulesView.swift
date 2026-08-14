import SwiftUI
import SwiftData

/// Lists the category rules you've taught the app by recategorizing merchants.
/// Rules can be added, edited and deleted here. Reached from Settings.
struct RulesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CategoryRule.matchText) private var rules: [CategoryRule]
    @State private var editing: CategoryRule?
    @State private var creating = false

    var body: some View {
        List {
            ForEach(rules) { rule in
                Button {
                    editing = rule
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: rule.category.symbol)
                            .foregroundStyle(rule.category.tint)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.matchText.capitalized).lineLimit(1)
                            Text(rule.category.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("Category Rules")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Label("Add Rule", systemImage: "plus") }
            }
        }
        .sheet(item: $editing) { RuleEditorView(rule: $0) }
        .sheet(isPresented: $creating) { RuleEditorView(rule: nil) }
        .overlay {
            if rules.isEmpty {
                ContentUnavailableView {
                    Label("No rules yet", systemImage: "wand.and.stars")
                } description: {
                    Text("Recategorize a transaction to teach the app a rule, or write one yourself.")
                } actions: {
                    Button("Add Rule") { creating = true }
                }
            }
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(rules[index]) }
        try? context.save()
    }
}
