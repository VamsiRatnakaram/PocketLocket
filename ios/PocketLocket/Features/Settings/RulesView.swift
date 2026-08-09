import SwiftUI
import SwiftData

/// Lists the category rules you've taught the app by recategorizing merchants,
/// with swipe-to-delete. Reached from Settings.
struct RulesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CategoryRule.matchText) private var rules: [CategoryRule]

    var body: some View {
        List {
            ForEach(rules) { rule in
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
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("Category Rules")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .overlay {
            if rules.isEmpty {
                ContentUnavailableView(
                    "No rules yet",
                    systemImage: "wand.and.stars",
                    description: Text("Recategorize a transaction to teach the app a rule — it'll appear here.")
                )
            }
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(rules[index]) }
        try? context.save()
    }
}
