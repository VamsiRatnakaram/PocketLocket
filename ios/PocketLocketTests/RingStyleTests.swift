import XCTest
@testable import PocketLocket

final class RingStyleTests: XCTestCase {
    /// The Home toolbar button renders `ringStyle.symbol` so the icon reflects
    /// the style currently on screen. It used to hardcode "circle.dashed",
    /// which is `progress`'s symbol -- so the button showed "progress" even
    /// while the donut was displayed.
    func testEachStyleHasADistinctSymbol() {
        let symbols = RingStyle.allCases.map(\.symbol)
        XCTAssertEqual(Set(symbols).count, RingStyle.allCases.count)
        XCTAssertFalse(symbols.contains(where: \.isEmpty))
    }

    func testSymbolsAreStable() {
        XCTAssertEqual(RingStyle.donut.symbol, "chart.pie.fill")
        XCTAssertEqual(RingStyle.progress.symbol, "circle.dashed")
    }

    func testRawValueRoundTrips() {
        for style in RingStyle.allCases {
            XCTAssertEqual(RingStyle(rawValue: style.rawValue), style)
        }
    }
}
