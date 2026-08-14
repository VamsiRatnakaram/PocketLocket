import XCTest
@testable import PocketLocket

/// These assert against the descriptor formats banks actually emit, rather than
/// the human-readable brand names. Several keyword entries were written as
/// marketing phrases ("aaa roadside", "lime bike") that no statement contains,
/// so they matched nothing.
final class MerchantDescriptorFormatTests: XCTestCase {
    func testAAAAppearsBareRatherThanAsAPhrase() {
        for descriptor in ["AAA WA MEMBERSHIP", "AAA 206-555-1212", "AAA CLUB PAYMENT"] {
            XCTAssertEqual(MerchantHeuristics.category(for: descriptor), .transport, descriptor)
        }
    }

    /// Lime bills as LIME*<per-ride reference>, so the reference varies per
    /// transaction and only the starred prefix is stable.
    func testLimeMatchesAnyStarredReference() {
        for descriptor in ["LIME*RIDE", "LIME*3XKQ2", "LIME*ABC123", "LIME*"] {
            XCTAssertEqual(MerchantHeuristics.category(for: descriptor), .transport, descriptor)
        }
    }

    /// The reason this keys on the `*` form instead of the bare "lime" token:
    /// the word is common in restaurant names.
    func testBareLimeIsNotTransport() {
        XCTAssertEqual(MerchantHeuristics.category(for: "LIME LEAF THAI RESTAURANT"), .food)
        // No food keyword matches this one, so the contract is only that the
        // brand word alone must not drag it into transport.
        XCTAssertNotEqual(MerchantHeuristics.category(for: "KEY LIME PIE CO"), .transport)
    }

    /// Processor prefixes also use the starred form, but there the brand is the
    /// payment rail, not the merchant, so they must fall through to the table.
    func testProcessorPrefixesStillResolveToTheMerchant() {
        XCTAssertEqual(MerchantHeuristics.category(for: "PAYPAL *NETFLIX.COM"), .entertainment)
        XCTAssertEqual(MerchantHeuristics.category(for: "GOOGLE *FIBER"), .housing)
    }

    /// "at&t" tokenizes to a single "at&t" token and never equals "att", which
    /// is how the descriptor actually reads.
    func testATTBillingDescriptors() {
        for descriptor in ["ATT*BILL PAYMENT", "ATT BILL", "T-MOBILE #1234"] {
            XCTAssertEqual(MerchantHeuristics.category(for: descriptor), .housing, descriptor)
        }
    }

    func testWashingtonFerriesUseAbbreviations() {
        XCTAssertEqual(MerchantHeuristics.category(for: "WSF SEATTLE"), .transport)
        XCTAssertEqual(MerchantHeuristics.category(for: "WSDOT FERRIES"), .transport)
    }

    /// Removed as redundant rather than fixed: the bare "utilities" entry
    /// already covers the real descriptor.
    func testSeattleUtilitiesStillResolves() {
        XCTAssertEqual(MerchantHeuristics.category(for: "SEATTLE PUBLIC UTILITIES"), .housing)
        XCTAssertEqual(MerchantHeuristics.category(for: "SEATTLE CITY LIGHT"), .housing)
    }
}
