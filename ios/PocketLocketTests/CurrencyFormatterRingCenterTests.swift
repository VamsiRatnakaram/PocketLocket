import XCTest
@testable import PocketLocket

/// The donut's center sits in a fixed-width hole, so these assertions are about
/// a layout budget: no cents, and never more than six digits.
final class CurrencyFormatterRingCenterTests: XCTestCase {
    private func digitCount(_ s: String) -> Int {
        s.filter(\.isNumber).count
    }

    func testDropsCents() {
        XCTAssertEqual(CurrencyFormatter.ringCenter(1234.56), "$1,235")
        XCTAssertEqual(CurrencyFormatter.ringCenter(0.49), "$0")
        XCTAssertFalse(CurrencyFormatter.ringCenter(99.99).contains("."))
    }

    func testSixDigitsRenderInFull() {
        XCTAssertEqual(CurrencyFormatter.ringCenter(999_999), "$999,999")
        XCTAssertEqual(digitCount(CurrencyFormatter.ringCenter(999_999)), 6)
    }

    func testAbbreviatesBeyondSixDigits() {
        XCTAssertEqual(CurrencyFormatter.ringCenter(1_000_000), "$1.0M")
        XCTAssertEqual(CurrencyFormatter.ringCenter(1_250_000), "$1.2M")  // half-even
        XCTAssertEqual(CurrencyFormatter.ringCenter(123_400_000), "$123M")
        XCTAssertEqual(CurrencyFormatter.ringCenter(2_500_000_000), "$2.5B")
        XCTAssertEqual(CurrencyFormatter.ringCenter(3_100_000_000_000), "$3.1T")
    }

    /// The actual contract, stated once over a wide sweep of magnitudes.
    func testNeverExceedsSixDigits() {
        var value = 0.75
        while value < 9_000_000_000_000 {
            let rendered = CurrencyFormatter.ringCenter(value)
            XCTAssertLessThanOrEqual(
                digitCount(rendered), 6,
                "\(value) rendered as \(rendered)"
            )
            XCTAssertFalse(
                rendered.hasSuffix(".00"),
                "\(value) rendered with cents as \(rendered)"
            )
            value *= 1.7
        }
    }

    func testNegatives() {
        XCTAssertEqual(CurrencyFormatter.ringCenter(-1_500_000), "-$1.5M")
        XCTAssertLessThanOrEqual(digitCount(CurrencyFormatter.ringCenter(-987_654.32)), 6)
    }

    /// `compact` is used for other labels and must keep its old behaviour.
    func testDoesNotChangeCompact() {
        XCTAssertEqual(CurrencyFormatter.compact(1_250_000), "$1,250,000")
    }
}
