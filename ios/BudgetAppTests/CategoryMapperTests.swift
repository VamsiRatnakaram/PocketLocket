import XCTest
@testable import BudgetApp

final class CategoryMapperTests: XCTestCase {
    func testKnownPrimaries() {
        XCTAssertEqual(CategoryMapper.map(primary: "FOOD_AND_DRINK"), .food)
        XCTAssertEqual(CategoryMapper.map(primary: "GROCERIES"), .groceries)
        XCTAssertEqual(CategoryMapper.map(primary: "GENERAL_MERCHANDISE"), .shopping)
        XCTAssertEqual(CategoryMapper.map(primary: "RENT_AND_UTILITIES"), .housing)
        XCTAssertEqual(CategoryMapper.map(primary: "HOME_IMPROVEMENT"), .housing)
        XCTAssertEqual(CategoryMapper.map(primary: "TRANSPORTATION"), .transport)
        XCTAssertEqual(CategoryMapper.map(primary: "TRAVEL"), .travel)
        XCTAssertEqual(CategoryMapper.map(primary: "ENTERTAINMENT"), .entertainment)
        XCTAssertEqual(CategoryMapper.map(primary: "MEDICAL"), .health)
        XCTAssertEqual(CategoryMapper.map(primary: "BANK_FEES"), .fees)
        XCTAssertEqual(CategoryMapper.map(primary: "INCOME"), .income)
        XCTAssertEqual(CategoryMapper.map(primary: "TRANSFER_OUT"), .transfer)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(CategoryMapper.map(primary: "food_and_drink"), .food)
    }

    func testUnknownAndNilFallBackToOther() {
        XCTAssertEqual(CategoryMapper.map(primary: "SOME_FUTURE_CATEGORY"), .other)
        XCTAssertEqual(CategoryMapper.map(primary: nil), .other)
    }

    func testIncomeAndTransferAreNotSpending() {
        XCTAssertFalse(SpendCategory.income.isSpending)
        XCTAssertFalse(SpendCategory.transfer.isSpending)
        XCTAssertTrue(SpendCategory.food.isSpending)
    }
}
