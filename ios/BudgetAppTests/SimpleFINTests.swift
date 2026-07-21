import XCTest
@testable import BudgetApp

final class SimpleFINTests: XCTestCase {
    func testDecodesAccountSet() throws {
        let json = """
        {"errlist":[],"accounts":[
          {"id":"Demo Checking","name":"SimpleFIN Checking","currency":"USD",
           "balance":"25767.79","available-balance":"25767.79","balance-date":1783036800,
           "transactions":[
             {"id":"1782979200","posted":1782979200,"amount":"-10.00","description":"Fishing bait"}
           ]}
        ]}
        """
        let set = try JSONDecoder().decode(SFAccountSet.self, from: Data(json.utf8))
        XCTAssertEqual(set.accounts.count, 1)
        XCTAssertEqual(set.accounts[0].name, "SimpleFIN Checking")
        XCTAssertEqual(set.accounts[0].balance, "25767.79")
        XCTAssertEqual(set.accounts[0].transactions?.count, 1)
        XCTAssertEqual(set.accounts[0].transactions?.first?.description, "Fishing bait")
    }

    func testDecodesNumericAmountAndSurfacesErrors() throws {
        let json = """
        {"errors":["Connection to Chase failed."],"accounts":[
          {"id":"a1","name":"Acct","currency":"USD","balance":"10.00","transactions":[
             {"id":"t1","posted":1782979200,"amount":-4.5,"description":"Numeric amount"}
          ]}
        ]}
        """
        let set = try JSONDecoder().decode(SFAccountSet.self, from: Data(json.utf8))
        XCTAssertEqual(set.errors, ["Connection to Chase failed."])
        XCTAssertEqual(set.accounts.first?.transactions?.first?.amount, "-4.5")
    }

    func testDecodesOptionalProviderCategory() throws {
        let json = """
        {"errors":[],"accounts":[
          {"id":"a1","transactions":[
            {"id":"t1","amount":"-4.50","description":"Coffee","extra":{"category":"restaurants"}}
          ]}
        ]}
        """
        let set = try JSONDecoder().decode(SFAccountSet.self, from: Data(json.utf8))
        XCTAssertEqual(set.accounts.first?.transactions?.first?.category, "restaurants")
    }

    func testAmountSignConversion() {
        // SimpleFIN: negative = money out; app: positive = spend.
        XCTAssertEqual(SimpleFINMapper.appAmount(from: "-10.00"), 10.0, accuracy: 0.001)
        XCTAssertEqual(SimpleFINMapper.appAmount(from: "1500.00"), -1500.0, accuracy: 0.001)
    }

    func testInferType() {
        XCTAssertEqual(SimpleFINMapper.inferType(name: "Chase Credit Card"), "credit")
        XCTAssertEqual(SimpleFINMapper.inferType(name: "Amex Platinum"), "credit")
      XCTAssertEqual(SimpleFINMapper.inferType(name: "Auto Loan"), "loan")
      XCTAssertEqual(SimpleFINMapper.inferType(name: "Home Mortgage"), "loan")
        XCTAssertEqual(SimpleFINMapper.inferType(name: "SimpleFIN Checking"), "depository")
    }
}
