import SwiftData
import XCTest
@testable import PocketLocket

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

    @MainActor
    func testDeletingSimpleFINDataPreservesOtherSources() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: AccountRecord.self,
            TransactionRecord.self,
            CategoryRule.self,
            configurations: configuration
        )
        let context = container.mainContext

        context.insert(AccountRecord(
            id: "sf-checking", plaidAccountId: "sf-checking", name: "Checking",
            officialName: nil, mask: nil, type: "depository", subtype: nil,
            currentBalance: 100, availableBalance: nil, isoCurrencyCode: "USD"
        ))
        context.insert(AccountRecord(
            id: "manual-cash", plaidAccountId: "manual-cash", name: "Cash",
            officialName: nil, mask: nil, type: "depository", subtype: "cash",
            currentBalance: 20, availableBalance: nil, isoCurrencyCode: "USD"
        ))
        context.insert(TransactionRecord(
            id: "sf-checking-t1", plaidTransactionId: "sf-checking-t1", name: "Coffee",
            merchantName: "Coffee", amount: 5, isoCurrencyCode: "USD", date: Date(),
            pending: false, categoryPrimary: nil, categoryDetailed: nil, logoURL: nil,
            accountId: "sf-checking"
        ))
        context.insert(TransactionRecord(
            id: "manual-t1", plaidTransactionId: "manual-t1", name: "Cash purchase",
            merchantName: "Cash purchase", amount: 10, isoCurrencyCode: "USD", date: Date(),
            pending: false, categoryPrimary: nil, categoryDetailed: nil, logoURL: nil,
            accountId: "manual-cash"
        ))
        try context.save()

        try SimpleFINDataStore.deleteSyncedData(in: context)

        let accountIDs = try context.fetch(FetchDescriptor<AccountRecord>()).map(\.id)
        let transactionIDs = try context.fetch(FetchDescriptor<TransactionRecord>()).map(\.id)
        XCTAssertEqual(accountIDs, ["manual-cash"])
        XCTAssertEqual(transactionIDs, ["manual-t1"])
    }
}