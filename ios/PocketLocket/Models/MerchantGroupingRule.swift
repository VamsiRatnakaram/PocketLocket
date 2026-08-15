import Foundation
import SwiftData

/// A user-owned override for one normalized statement descriptor.
///
/// Category rules intentionally use token containment so they can generalize.
/// Grouping rules do the opposite: they match one exact `groupingKey`, because
/// a broad merchant-name guess is what makes unrelated transactions collapse
/// into the same Analysis row.
@Model
final class MerchantGroupingRule {
    @Attribute(.unique) var sourceKey: String
    var groupID: String
    var groupName: String
    var createdAt: Date

    init(
        sourceKey: String,
        groupID: String = UUID().uuidString,
        groupName: String,
        createdAt: Date = .now
    ) {
        let key = MerchantNormalizer.groupingKey(sourceKey)
        self.sourceKey = key
        self.groupID = groupID
        self.groupName = Self.cleanedGroupName(groupName, fallback: key)
        self.createdAt = createdAt
    }

    static func cleanedGroupName(_ value: String, fallback: String) -> String {
        let cleaned = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return cleaned.isEmpty ? fallback : cleaned
    }
}

/// Plain actor-safe value copied from the SwiftData model on the main actor.
struct MerchantGroupingRuleSpec: Hashable, Sendable {
    let sourceKey: String
    let groupID: String
    let groupName: String

    init(sourceKey: String, groupID: String, groupName: String) {
        let key = MerchantNormalizer.groupingKey(sourceKey)
        self.sourceKey = key
        self.groupID = groupID
        self.groupName = MerchantGroupingRule.cleanedGroupName(groupName, fallback: key)
    }

    init(rule: MerchantGroupingRule) {
        self.init(
            sourceKey: rule.sourceKey,
            groupID: rule.groupID,
            groupName: rule.groupName
        )
    }
}

@MainActor
enum MerchantGroupingAssignment {
    /// Assigns every selected exact descriptor to one user-named group.
    ///
    /// Sources removed from the original group receive an explicit self-rule.
    /// That is what makes "split" durable: deleting their old rule would merely
    /// hand them back to the fuzzy automatic grouper.
    static func apply(
        groupName: String,
        selectedSources: Set<String>,
        originalSources: Set<String>,
        rules: [MerchantGroupingRule],
        in context: ModelContext
    ) throws {
        let selected = Set(selectedSources.map(MerchantNormalizer.groupingKey))
        let original = Set(originalSources.map(MerchantNormalizer.groupingKey))
        var rulesBySource = Dictionary(
            rules.map { ($0.sourceKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let targetGroupID = rules.first {
            original.contains($0.sourceKey) && selected.contains($0.sourceKey)
        }?.groupID ?? UUID().uuidString

        for source in original.subtracting(selected) {
            upsert(
                source: source,
                groupID: UUID().uuidString,
                groupName: source,
                rulesBySource: &rulesBySource,
                context: context
            )
        }
        for source in selected {
            upsert(
                source: source,
                groupID: targetGroupID,
                groupName: groupName,
                rulesBySource: &rulesBySource,
                context: context
            )
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    static func reset(
        sources: Set<String>,
        rules: [MerchantGroupingRule],
        in context: ModelContext
    ) throws {
        let normalized = Set(sources.map(MerchantNormalizer.groupingKey))
        for rule in rules where normalized.contains(rule.sourceKey) {
            context.delete(rule)
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func upsert(
        source: String,
        groupID: String,
        groupName: String,
        rulesBySource: inout [String: MerchantGroupingRule],
        context: ModelContext
    ) {
        if let existing = rulesBySource[source] {
            existing.groupID = groupID
            existing.groupName = MerchantGroupingRule.cleanedGroupName(groupName, fallback: source)
        } else {
            let rule = MerchantGroupingRule(
                sourceKey: source,
                groupID: groupID,
                groupName: groupName
            )
            context.insert(rule)
            rulesBySource[source] = rule
        }
    }
}
