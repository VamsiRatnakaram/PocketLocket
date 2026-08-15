import XCTest
@testable import PocketLocket

final class MerchantDetailBuilderTests: XCTestCase {
    private func transaction(
        id: String,
        name: String,
        amount: Double = 10,
        month: Int = 1
    ) -> TransactionRecord {
        TransactionRecord(
            id: id,
            plaidTransactionId: id,
            name: name,
            merchantName: name,
            amount: amount,
            isoCurrencyCode: "USD",
            date: Calendar.current.date(
                from: DateComponents(year: 2026, month: month, day: 1)
            )!,
            pending: false,
            categoryPrimary: nil,
            categoryDetailed: nil,
            logoURL: nil,
            accountId: nil
        )
    }

    private var stats: MerchantAnalytics.MerchantStats {
        MerchantAnalytics.MerchantStats(
            groupingID: "auto:target cafe",
            name: "Target Cafe",
            category: .food,
            visitCount: 3,
            totalSpent: 30,
            averagePerVisit: 10,
            firstDate: .distantPast,
            lastDate: .now,
            trend: .flat,
            aliases: [MerchantNormalizer.groupingKey("Target Cafe")]
        )
    }

    func testBuilderResolvesCategoriesOnlyForMatchingMerchant() {
        let unrelated = (0..<500).map {
            transaction(id: "other-\($0)", name: "Unrelated Merchant \($0)")
        }
        let matching = [
            transaction(id: "target-1", name: "Target Cafe", month: 1),
            transaction(id: "target-2", name: "Target Cafe", month: 1),
            transaction(id: "target-3", name: "Target Cafe", month: 2),
            transaction(id: "excluded", name: "Target Cafe", month: 2),
            transaction(id: "refund", name: "Target Cafe", amount: -5, month: 2),
        ]
        var categoryResolutions = 0

        let content = MerchantDetailBuilder.build(
            stats: stats,
            transactions: unrelated + matching
        ) { transaction in
            categoryResolutions += 1
            return transaction.id == "excluded" ? .transfer : .food
        }

        XCTAssertEqual(
            categoryResolutions,
            4,
            "unrelated and negative transactions must be rejected before category resolution"
        )
        XCTAssertEqual(content.items.map(\.id).sorted(), ["target-1", "target-2", "target-3"])
        XCTAssertEqual(content.monthly.count, 2)
        XCTAssertEqual(content.monthly.map(\.amount).reduce(0, +), 30)
    }

    func testBuilderUsesEffectiveReimbursedAmount() {
        let expense = transaction(id: "target-1", name: "Target Cafe", amount: 30)
        let content = MerchantDetailBuilder.build(
            stats: stats,
            transactions: [expense],
            effectiveAmountFor: { _ in 10 },
            categoryFor: { _ in .food }
        )

        XCTAssertEqual(content.items.first?.reimbursedAmount, 20)
        XCTAssertEqual(content.monthly.first?.amount, 10)
    }
}
