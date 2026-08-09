import XCTest
@testable import PocketLocket

@MainActor
final class TransactionDedupTests: XCTestCase {
    func testSourceExtraction() {
        XCTAssertEqual(TransactionDedup.source(of: "sf-acct1-999"), "sf")
        XCTAssertEqual(TransactionDedup.source(of: "ofx-abc"), "ofx")
        XCTAssertEqual(TransactionDedup.source(of: "csv-xyz"), "csv")
    }

    func testKeyNormalizesName() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let k1 = TransactionDedup.key(date: date, amount: 12.34, name: "Starbucks #123")
        let k2 = TransactionDedup.key(date: date, amount: 12.34, name: "STARBUCKS 123")
        XCTAssertEqual(k1, k2)
    }

    func testCrossSourceDuplicateDetection() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let key = TransactionDedup.key(date: date, amount: 5.0, name: "Coffee")
        let index = [key: "sf"]
        // An import of the same real transaction is a cross-source duplicate.
        XCTAssertTrue(TransactionDedup.isCrossSourceDuplicate(id: "ofx-1", date: date, amount: 5.0, name: "Coffee", in: index))
        // Another SimpleFIN transaction with the same key is NOT (same source).
        XCTAssertFalse(TransactionDedup.isCrossSourceDuplicate(id: "sf-a-2", date: date, amount: 5.0, name: "Coffee", in: index))
        // A different amount is not a duplicate.
        XCTAssertFalse(TransactionDedup.isCrossSourceDuplicate(id: "ofx-3", date: date, amount: 9.0, name: "Coffee", in: index))
    }
}
