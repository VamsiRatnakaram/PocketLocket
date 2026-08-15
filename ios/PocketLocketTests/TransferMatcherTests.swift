import XCTest
@testable import PocketLocket

final class TransferMatcherTests: XCTestCase {
    private let checking = "acct-checking"
    private let card = "acct-card"
    private let savings = "acct-savings"

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(TimeInterval(offset) * 86_400)
    }

    private func candidate(_ id: String, _ account: String, _ amount: Double, _ dayOffset: Int)
        -> TransferMatcher.Candidate {
        TransferMatcher.Candidate(id: id, accountId: account, amount: amount, date: day(dayOffset))
    }

    private func candidate(_ id: String, _ account: String, _ amount: Double, _ dayOffset: Int, currency: String)
        -> TransferMatcher.Candidate {
        TransferMatcher.Candidate(id: id, accountId: account, amount: amount, date: day(dayOffset), currency: currency)
    }

    /// The core case: a bank debit whose descriptor gives nothing away, paired
    /// to the card credit purely by the balancing amount.
    func testMatchesCardPayoffAcrossAccounts() {
        let matches = TransferMatcher.match(
            candidates: [
                candidate("out", checking, 500, 0),
                candidate("in", card, -500, 1),
            ],
            transferAccountIds: [card]
        )

        XCTAssertEqual(matches.count, 2)
        XCTAssertNotNil(matches["out"])
        XCTAssertEqual(matches["out"], matches["in"])
    }

    /// A purchase and its refund on the same card balance perfectly but never
    /// left your accounts. Requiring two different accounts is what keeps them
    /// out of the budget-exclusion path.
    func testIgnoresPurchaseAndRefundOnSameAccount() {
        let matches = TransferMatcher.match(
            candidates: [
                candidate("purchase", card, 50, 0),
                candidate("refund", card, -50, 2),
            ],
            transferAccountIds: [card]
        )

        XCTAssertTrue(matches.isEmpty)
    }

    /// Two checking accounts coincidentally seeing +$50 and -$50 is a far more
    /// likely coincidence than a transfer, so a credit/loan account must be
    /// involved.
    func testRequiresACreditOrLoanAccountOnOneSide() {
        let matches = TransferMatcher.match(
            candidates: [
                candidate("out", checking, 50, 0),
                candidate("in", savings, -50, 0),
            ],
            transferAccountIds: [card]
        )

        XCTAssertTrue(matches.isEmpty)
    }

    /// A payment initiated before a weekend or holiday can take several
    /// business days to post on both sides, so a same-week gap has to pair.
    func testMatchesAcrossASettlementDelay() {
        let matches = TransferMatcher.match(
            candidates: [
                candidate("out", checking, 500, 0),
                candidate("in", card, -500, 6),
            ],
            transferAccountIds: [card]
        )

        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches["out"], matches["in"])
    }

    /// Just outside the window, to pin the boundary rather than passing
    /// trivially on a gap no plausible setting would accept.
    func testRespectsPostingWindow() {
        let matches = TransferMatcher.match(
            candidates: [
                candidate("out", checking, 500, 0),
                candidate("in", card, -500, 9),
            ],
            transferAccountIds: [card]
        )

        XCTAssertTrue(matches.isEmpty)
    }

    /// Two payments close enough that every leg is in range of every other.
    /// Only the closest-posting rule stops the second payment from claiming
    /// the first one's credit.
    func testClosestPostingWinsWhenAllLegsAreInRange() {
        let matches = TransferMatcher.match(
            candidates: [
                candidate("out-first", checking, 500, 0),
                candidate("in-first", card, -500, 1),
                candidate("out-second", checking, 500, 5),
                candidate("in-second", card, -500, 6),
            ],
            transferAccountIds: [card]
        )

        XCTAssertEqual(matches.count, 4)
        XCTAssertEqual(matches["out-first"], matches["in-first"])
        XCTAssertEqual(matches["out-second"], matches["in-second"])
        XCTAssertEqual(Set(matches.values).count, 2)
    }

    /// Three identical payments in a month must consume three distinct credits.
    /// A naive first-match would latch every debit onto the nearest credit and
    /// leave two payments counted as spending.
    func testEachLegIsUsedOnlyOnce() {
        let matches = TransferMatcher.match(
            candidates: [
                candidate("out1", checking, 500, 0),
                candidate("out2", checking, 500, 10),
                candidate("out3", checking, 500, 20),
                candidate("in1", card, -500, 1),
                candidate("in2", card, -500, 11),
                candidate("in3", card, -500, 21),
            ],
            transferAccountIds: [card]
        )

        XCTAssertEqual(matches.count, 6)
        XCTAssertEqual(matches["out1"], matches["in1"])
        XCTAssertEqual(matches["out2"], matches["in2"])
        XCTAssertEqual(matches["out3"], matches["in3"])
        XCTAssertEqual(Set(matches.values).count, 3)
    }

    /// With more debits than credits, the closest pairing wins and the extra
    /// debit stays in the budget rather than being silently written off.
    func testUnbalancedLegsLeaveTheExtraUnmatched() {
        let matches = TransferMatcher.match(
            candidates: [
                candidate("out-near", checking, 500, 0),
                candidate("out-far", checking, 500, 4),
                candidate("in", card, -500, 0),
            ],
            transferAccountIds: [card]
        )

        XCTAssertEqual(matches.count, 2)
        XCTAssertNotNil(matches["out-near"])
        XCTAssertNil(matches["out-far"])
    }

    func testDifferentAmountsDoNotPair() {
        let matches = TransferMatcher.match(
            candidates: [
                candidate("out", checking, 500, 0),
                candidate("in", card, -499.99, 0),
            ],
            transferAccountIds: [card]
        )

        XCTAssertTrue(matches.isEmpty)
    }

    /// Pair ids are derived from the leg ids, so re-running over unchanged data
    /// rewrites identical values instead of churning the store.
    func testMatchingIsStableAcrossRuns() {
        let candidates = [
            candidate("out", checking, 500, 0),
            candidate("in", card, -500, 1),
            candidate("other-out", checking, 120, 3),
            candidate("other-in", card, -120, 3),
        ]

        let first = TransferMatcher.match(candidates: candidates, transferAccountIds: [card])
        let second = TransferMatcher.match(candidates: candidates.reversed(), transferAccountIds: [card])

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 4)
    }

    func testSkipsZeroAmountsAndMissingAccounts() {
        let matches = TransferMatcher.match(
            candidates: [
                candidate("zero-out", checking, 0, 0),
                candidate("zero-in", card, 0, 0),
                candidate("no-account", "", 75, 0),
                candidate("in", card, -75, 0),
            ],
            transferAccountIds: [card]
        )

        XCTAssertTrue(matches.isEmpty)
    }

    func testTransferAccountTypeDetection() {
        XCTAssertTrue(TransferMatcher.isTransferAccountType("credit"))
        XCTAssertTrue(TransferMatcher.isTransferAccountType("loan"))
        XCTAssertTrue(TransferMatcher.isTransferAccountType("Credit"))
        XCTAssertFalse(TransferMatcher.isTransferAccountType("depository"))
        XCTAssertFalse(TransferMatcher.isTransferAccountType(nil))
        XCTAssertTrue(
            TransferMatcher.isBidirectionalTransferAccountType("investment")
        )
        XCTAssertFalse(
            TransferMatcher.isBidirectionalTransferAccountType("credit")
        )
    }

    func testMatchesInvestmentWithdrawalToBankDeposit() {
        let investment = "investment"
        let matches = TransferMatcher.match(
            candidates: [
                candidate("fidelity-out", investment, 4_005.31, 0),
                candidate("bank-in", checking, -4_005.31, 0),
            ],
            transferAccountIds: [],
            bidirectionalTransferAccountIds: [investment]
        )

        XCTAssertEqual(matches["fidelity-out"], matches["bank-in"])
        XCTAssertNotNil(matches["fidelity-out"])
    }

    /// Numerically equal amounts in different currencies are not the two halves
    /// of anything; pairing them would drop real spending out of the budget.
    func testDoesNotMatchAcrossCurrencies() {
        let matches = TransferMatcher.match(
            candidates: [
                candidate("out", checking, 500, 0, currency: "EUR"),
                candidate("in", card, -500, 1, currency: "USD"),
            ],
            transferAccountIds: [card]
        )
        XCTAssertTrue(matches.isEmpty)
    }

    /// A card purchase and an unrelated equal deposit into checking share an
    /// amount and a week, but money never moved between the two. Requiring the
    /// credit/loan account to hold the *inflow* leg rejects it.
    func testDoesNotMatchCardPurchaseAgainstCheckingDeposit() {
        let matches = TransferMatcher.match(
            candidates: [
                candidate("card-purchase", card, 500, 0),
                candidate("checking-deposit", checking, -500, 1),
            ],
            transferAccountIds: [card]
        )
        XCTAssertTrue(matches.isEmpty)
    }

    /// Taking the globally closest edge first strands the day-7 payment outside
    /// the window of the only inflow left over. Maximum matching re-homes the
    /// day-0 payment so both payoffs are recognized.
    func testGreedyClosestPairDoesNotStrandASecondPayoff() {
        let matches = TransferMatcher.match(
            candidates: [
                candidate("out-a", checking, 500, 0),
                candidate("out-b", checking, 500, 7),
                candidate("in-a", card, -500, 1),
                candidate("in-b", card, -500, -8),
            ],
            transferAccountIds: [card]
        )
        XCTAssertEqual(matches.count, 4, "both payoffs should pair")
        XCTAssertEqual(matches["out-b"], matches["in-a"])
        XCTAssertEqual(matches["out-a"], matches["in-b"])
    }
}
