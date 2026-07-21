import SwiftData
import XCTest
@testable import BudgetApp

final class AppModelContainerTests: XCTestCase {
    @MainActor
    func testInMemoryContainerCanCreateTheAppSchema() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: AccountRecord.self,
            TransactionRecord.self,
            CategoryRule.self,
            configurations: configuration
        )

        XCTAssertNotNil(container.mainContext)
    }
}