import XCTest
import SwiftData
@testable import BudgetApp

@MainActor
final class BackupServiceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: AccountRecord.self, TransactionRecord.self, CategoryRule.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func seed(_ context: ModelContext) throws {
        context.insert(AccountRecord(
            id: "sf-1", plaidAccountId: "sf-1", name: "Checking", officialName: nil,
            mask: nil, type: "depository", subtype: nil, currentBalance: 100,
            availableBalance: nil, isoCurrencyCode: "USD"
        ))
        context.insert(TransactionRecord(
            id: "sf-1-a", plaidTransactionId: "sf-1-a", name: "Coffee", merchantName: "Coffee",
            amount: 4.5, isoCurrencyCode: "USD", date: .now, pending: false,
            categoryPrimary: nil, categoryDetailed: nil, logoURL: nil, accountId: "sf-1"
        ))
        context.insert(CategoryRule(matchText: "coffee", category: .food))
        try context.save()
    }

    func testEncryptedRoundTripPreservesData() throws {
        let source = try makeContext()
        try seed(source)

        let file = try BackupService.exportEncrypted(password: "hunter2", context: source)

        // The encrypted file must not contain the plaintext merchant name.
        let asText = String(decoding: file, as: UTF8.self)
        XCTAssertFalse(asText.contains("Coffee"))

        let dest = try makeContext()
        let inserted = try BackupService.importEncrypted(file, password: "hunter2", context: dest)
        XCTAssertEqual(inserted, 1)
        XCTAssertEqual(try dest.fetch(FetchDescriptor<TransactionRecord>()).count, 1)
        XCTAssertEqual(try dest.fetch(FetchDescriptor<AccountRecord>()).count, 1)
        XCTAssertEqual(try dest.fetch(FetchDescriptor<CategoryRule>()).count, 1)
    }

    func testWrongPasswordFails() throws {
        let source = try makeContext()
        try seed(source)
        let file = try BackupService.exportEncrypted(password: "correct-horse", context: source)

        let dest = try makeContext()
        XCTAssertThrowsError(try BackupService.importEncrypted(file, password: "wrong", context: dest))
    }

    func testImportIsIdempotent() throws {
        let source = try makeContext()
        try seed(source)
        let file = try BackupService.exportEncrypted(password: "pw", context: source)

        let dest = try makeContext()
        _ = try BackupService.importEncrypted(file, password: "pw", context: dest)
        let secondPass = try BackupService.importEncrypted(file, password: "pw", context: dest)
        XCTAssertEqual(secondPass, 0) // nothing new the second time
        XCTAssertEqual(try dest.fetch(FetchDescriptor<TransactionRecord>()).count, 1)
    }
}
