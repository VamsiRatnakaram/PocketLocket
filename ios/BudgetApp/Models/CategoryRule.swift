import Foundation
import SwiftData

/// A user-taught categorization rule: when a transaction's merchant/name
/// contains `matchText`, force it into `category`. Created when you recategorize
/// a transaction ("always categorize X as …").
@Model
final class CategoryRule {
    @Attribute(.unique) var matchText: String
    var categoryRaw: String
    var createdAt: Date

    init(matchText: String, category: SpendCategory, createdAt: Date = .now) {
        self.matchText = matchText.lowercased()
        self.categoryRaw = category.rawValue
        self.createdAt = createdAt
    }

    var category: SpendCategory { SpendCategory(rawValue: categoryRaw) ?? .other }
}
