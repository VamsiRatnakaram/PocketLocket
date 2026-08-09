import XCTest
@testable import PocketLocket

final class SavingsAdvisorTests: XCTestCase {
    func testEmptyWhenNoSpending() {
        XCTAssertTrue(SavingsAdvisor.suggestions([], monthlyBudget: 3000).isEmpty)
    }

    func testSubscriptionsTopCategoryAndSurplus() {
        let inputs = [
            SavingsAdvisor.Input(title: "Netflix", amount: 15.99, category: .entertainment, isSubscription: true),
            SavingsAdvisor.Input(title: "Rent", amount: 1500, category: .housing, isSubscription: false),
            SavingsAdvisor.Input(title: "Paycheck", amount: -2500, category: .income, isSubscription: false),
        ]
        let suggestions = SavingsAdvisor.suggestions(inputs, monthlyBudget: 3000)

        XCTAssertTrue(suggestions.contains { $0.title.localizedCaseInsensitiveContains("subscription") })
        XCTAssertTrue(suggestions.contains { $0.title.contains("Housing") })
        XCTAssertTrue(suggestions.contains { $0.title.localizedCaseInsensitiveContains("surplus") })
    }

    func testOverBudgetSuggestion() {
        let inputs = [
            SavingsAdvisor.Input(title: "Rent", amount: 4000, category: .housing, isSubscription: false)
        ]
        let suggestions = SavingsAdvisor.suggestions(inputs, monthlyBudget: 3000)
        XCTAssertTrue(suggestions.contains { $0.title.localizedCaseInsensitiveContains("over budget") })
    }

    func testDiningSuggestionRequiresFourPurchases() {
        let dining = (0..<4).map {
            SavingsAdvisor.Input(title: "Cafe \($0)", amount: 12, category: .food, isSubscription: false)
        }
        let suggestions = SavingsAdvisor.suggestions(dining, monthlyBudget: 3000)
        XCTAssertTrue(suggestions.contains { $0.title.localizedCaseInsensitiveContains("dining") })
    }

    func testTransactionQuestionContextIncludesGroundedTotalsAndRows() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-05T12:00:00Z"))
        let context = TransactionQuestionContext.make(
            entries: [
                .init(date: date, title: "Corner Cafe", amount: 12.50, currency: "USD", category: "Dining Out"),
                .init(date: date, title: "Market", amount: 23, currency: "USD", category: "Groceries"),
                .init(date: date, title: "Paycheck", amount: -100, currency: "USD", category: "Income"),
            ],
            monthlyBudget: 500
        )

        XCTAssertTrue(context.contains("Monthly budget: USD 500.00"))
        XCTAssertTrue(context.contains("2026-08: spending USD 35.50; inflow USD 100.00"))
        XCTAssertTrue(context.contains("Dining Out: USD 12.50"))
        XCTAssertTrue(context.contains("2026-08-05 | expense USD 12.50 | Dining Out | Corner Cafe"))
    }
}
