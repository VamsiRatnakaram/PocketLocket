import SwiftData
import XCTest
@testable import PocketLocket

@MainActor
final class MerchantGroupingAssignmentTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: MerchantGroupingRule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    func testApplyMergesSelectedSourcesAndExplicitlySplitsRemovedSource() throws {
        let context = try makeContext()

        try MerchantGroupingAssignment.apply(
            groupName: "Work Cafe",
            selectedSources: ["MS CAFE 34", "CAFE 34"],
            originalSources: ["MS CAFE 34", "CAFE 34", "MS CM FOODHALL 6"],
            rules: [],
            in: context
        )

        let rules = try context.fetch(FetchDescriptor<MerchantGroupingRule>())
        let bySource = Dictionary(uniqueKeysWithValues: rules.map { ($0.sourceKey, $0.groupName) })
        XCTAssertEqual(bySource["Ms Cafe 34"], "Work Cafe")
        XCTAssertEqual(bySource["Cafe 34"], "Work Cafe")
        XCTAssertEqual(bySource["Ms Cm Foodhall 6"], "Ms Cm Foodhall 6")
        let selectedIDs = Set(
            rules.filter { $0.groupName == "Work Cafe" }.map(\.groupID)
        )
        XCTAssertEqual(selectedIDs.count, 1)
        XCTAssertNotEqual(
            rules.first { $0.sourceKey == "Ms Cm Foodhall 6" }?.groupID,
            selectedIDs.first
        )
    }

    func testApplyRenamesExistingGroupAndMovesAnotherSourceIntoIt() throws {
        let context = try makeContext()
        let cafe = MerchantGroupingRule(sourceKey: "CAFE 34", groupName: "Cafe")
        let prefixed = MerchantGroupingRule(sourceKey: "MS CAFE 34", groupName: "Cafe")
        let other = MerchantGroupingRule(sourceKey: "CAFE TURKO", groupName: "Cafe Turko")
        [cafe, prefixed, other].forEach(context.insert)
        try context.save()

        try MerchantGroupingAssignment.apply(
            groupName: "Office Cafes",
            selectedSources: ["CAFE 34", "MS CAFE 34", "CAFE TURKO"],
            originalSources: ["CAFE 34", "MS CAFE 34"],
            rules: [cafe, prefixed, other],
            in: context
        )

        let rules = try context.fetch(FetchDescriptor<MerchantGroupingRule>())
        XCTAssertEqual(Set(rules.map(\.groupName)), ["Office Cafes"])
    }

    func testResetDeletesOnlyAffectedSources() throws {
        let context = try makeContext()
        let cafe = MerchantGroupingRule(sourceKey: "CAFE 34", groupName: "Work Cafe")
        let prefixed = MerchantGroupingRule(sourceKey: "MS CAFE 34", groupName: "Work Cafe")
        let lime = MerchantGroupingRule(sourceKey: "LIME", groupName: "Lime")
        [cafe, prefixed, lime].forEach(context.insert)
        try context.save()

        try MerchantGroupingAssignment.reset(
            sources: ["CAFE 34", "MS CAFE 34"],
            rules: [cafe, prefixed, lime],
            in: context
        )

        let remaining = try context.fetch(FetchDescriptor<MerchantGroupingRule>())
        XCTAssertEqual(remaining.map(\.sourceKey), ["Lime"])
    }
}
