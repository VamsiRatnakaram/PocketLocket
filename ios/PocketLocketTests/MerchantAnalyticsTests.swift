import XCTest
@testable import PocketLocket

final class MerchantAnalyticsTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int = 1) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    // MARK: - MerchantNormalizer

    func testNormalizerStripsStoreNumbersAndCase() {
        XCTAssertEqual(MerchantNormalizer.normalize("STARBUCKS #4521"), "Starbucks")
        XCTAssertEqual(MerchantNormalizer.normalize("starbucks 04521"), "Starbucks")
        XCTAssertEqual(MerchantNormalizer.normalize("Chipotle"), "Chipotle")
    }

    func testNormalizerStripsPOSPrefixes() {
        XCTAssertEqual(MerchantNormalizer.normalize("SQ *Blue Bottle Coffee"), "Blue Bottle Coffee")
    }

    /// The reference behind the star is different on every charge, so without
    /// this one merchant showed up as dozens of one-visit entries.
    func testNormalizerDropsPerTransactionReferenceAfterStar() {
        XCTAssertEqual(MerchantNormalizer.normalize("LIME*1"), "Lime")
        XCTAssertEqual(MerchantNormalizer.normalize("LIME*2"), "Lime")
        XCTAssertEqual(MerchantNormalizer.normalize("Lime"), "Lime")
        XCTAssertEqual(MerchantNormalizer.normalize("LIME *RIDE"), "Lime")
        XCTAssertEqual(MerchantNormalizer.normalize("AMZN Mktp US*2H4KJ"), "Amzn Mktp Us")
        XCTAssertEqual(MerchantNormalizer.normalize("UBER *TRIP"), "Uber")
    }

    /// A processor puts its own name first, so there the merchant is the
    /// *second* half — the opposite of every other star descriptor.
    func testNormalizerKeepsMerchantAfterProcessorPrefix() {
        XCTAssertEqual(MerchantNormalizer.normalize("SQ *Blue Bottle Coffee"), "Blue Bottle Coffee")
        XCTAssertEqual(MerchantNormalizer.normalize("PAYPAL *STEAM GAMES"), "Steam Games")
        XCTAssertEqual(MerchantNormalizer.normalize("TST* Little Star Pizza"), "Little Star Pizza")
    }

    func testNormalizerHandlesUnusableMerchantHalf() {
        // A leading star is the processor form with the processor missing.
        XCTAssertEqual(MerchantNormalizer.normalize("*Lime Ride"), "Lime Ride")
        // Too short in front of the star to identify a merchant, so keep the
        // descriptor rather than reducing it to two letters.
        XCTAssertEqual(MerchantNormalizer.normalize("XY*Some Merchant"), "Xy*some Merchant")
    }

    func testNormalizerStripsTrailingState() {
        XCTAssertEqual(MerchantNormalizer.normalize("Trader Joes CA"), "Trader Joes")
    }

    // MARK: - merchantStats

    func testMerchantStatsCountsVisitsAndTotals() {
        let inputs = [
            MerchantAnalytics.Input(title: "Chipotle #1234", amount: 12, category: .food, date: date(2025, 1, 5)),
            MerchantAnalytics.Input(title: "Chipotle 01234", amount: 14, category: .food, date: date(2025, 2, 5)),
            MerchantAnalytics.Input(title: "Chipotle", amount: 13, category: .food, date: date(2025, 3, 5)),
        ]

        let stats = MerchantAnalytics.merchantStats(inputs)
        XCTAssertEqual(stats.count, 1)
        let chipotle = try! XCTUnwrap(stats.first)
        XCTAssertEqual(chipotle.name, "Chipotle")
        XCTAssertEqual(chipotle.visitCount, 3)
        XCTAssertEqual(chipotle.totalSpent, 39, accuracy: 0.0001)
        XCTAssertEqual(chipotle.averagePerVisit, 13, accuracy: 0.0001)
        XCTAssertEqual(chipotle.category, .food)
    }

    func testMerchantStatsExcludesIncomeTransfersAndRefunds() {
        let inputs = [
            MerchantAnalytics.Input(title: "Payroll", amount: 3000, category: .income, date: date(2025, 1, 1)),
            MerchantAnalytics.Input(title: "Venmo", amount: 50, category: .transfer, date: date(2025, 1, 2)),
            MerchantAnalytics.Input(title: "Amazon", amount: -20, category: .shopping, date: date(2025, 1, 3)),
            MerchantAnalytics.Input(title: "Amazon", amount: 40, category: .shopping, date: date(2025, 1, 4)),
        ]

        let stats = MerchantAnalytics.merchantStats(inputs)
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats.first?.name, "Amazon")
        XCTAssertEqual(stats.first?.totalSpent ?? 0, 40, accuracy: 0.0001)
    }

    func testMerchantStatsEmptyForNoSpending() {
        XCTAssertTrue(MerchantAnalytics.merchantStats([]).isEmpty)
    }

    // MARK: - topByFrequency / topBySpend

    func testTopByFrequencyOrdersByVisitCount() {
        let inputs = [
            MerchantAnalytics.Input(title: "Coffee Shop", amount: 5, category: .food, date: date(2025, 1, 1)),
            MerchantAnalytics.Input(title: "Coffee Shop", amount: 5, category: .food, date: date(2025, 1, 2)),
            MerchantAnalytics.Input(title: "Coffee Shop", amount: 5, category: .food, date: date(2025, 1, 3)),
            MerchantAnalytics.Input(title: "Steakhouse", amount: 100, category: .food, date: date(2025, 1, 4)),
        ]

        let stats = MerchantAnalytics.merchantStats(inputs)
        let byFrequency = MerchantAnalytics.topByFrequency(stats)
        XCTAssertEqual(byFrequency.first?.name, "Coffee Shop")

        let bySpend = MerchantAnalytics.topBySpend(stats)
        XCTAssertEqual(bySpend.first?.name, "Steakhouse")
    }

    // MARK: - recurringMerchants

    func testRecurringMerchantsRequiresDistinctMonths() {
        let inputs = [
            MerchantAnalytics.Input(title: "Gym", amount: 30, category: .services, date: date(2025, 1, 1)),
            MerchantAnalytics.Input(title: "Gym", amount: 30, category: .services, date: date(2025, 2, 1)),
            MerchantAnalytics.Input(title: "Gym", amount: 30, category: .services, date: date(2025, 3, 1)),
            MerchantAnalytics.Input(title: "One-off Store", amount: 200, category: .shopping, date: date(2025, 1, 15)),
        ]

        let recurring = MerchantAnalytics.recurringMerchants(inputs, minMonths: 3)
        XCTAssertEqual(recurring.map(\.name), ["Gym"])
    }

    func testRecurringMerchantsSameMonthMultipleVisitsDoesNotQualify() {
        let inputs = [
            MerchantAnalytics.Input(title: "Diner", amount: 15, category: .food, date: date(2025, 1, 1)),
            MerchantAnalytics.Input(title: "Diner", amount: 15, category: .food, date: date(2025, 1, 10)),
            MerchantAnalytics.Input(title: "Diner", amount: 15, category: .food, date: date(2025, 1, 20)),
        ]

        // 3 visits, but all within a single calendar month — should not qualify for minMonths: 3.
        let recurring = MerchantAnalytics.recurringMerchants(inputs, minMonths: 3)
        XCTAssertTrue(recurring.isEmpty)
    }

    // MARK: - categoryMonthlyTotals / categoryAverages

    func testCategoryMonthlyTotalsBucketsByMonth() {
        let inputs = [
            MerchantAnalytics.Input(title: "Whole Foods", amount: 100, category: .groceries, date: date(2025, 1, 5)),
            MerchantAnalytics.Input(title: "Trader Joes", amount: 50, category: .groceries, date: date(2025, 1, 20)),
            MerchantAnalytics.Input(title: "Whole Foods", amount: 80, category: .groceries, date: date(2025, 2, 5)),
        ]

        let monthly = MerchantAnalytics.categoryMonthlyTotals(inputs)
        XCTAssertEqual(monthly.count, 2)
        XCTAssertEqual(monthly[0].amount, 150, accuracy: 0.0001)
        XCTAssertEqual(monthly[1].amount, 80, accuracy: 0.0001)
    }

    func testCategoryAveragesComputesMeanAndTrend() {
        let inputs = [
            MerchantAnalytics.Input(title: "Groceries A", amount: 100, category: .groceries, date: date(2025, 1, 5)),
            MerchantAnalytics.Input(title: "Groceries A", amount: 300, category: .groceries, date: date(2025, 2, 5)),
        ]

        let averages = MerchantAnalytics.categoryAverages(inputs)
        XCTAssertEqual(averages.count, 1)
        let groceries = try! XCTUnwrap(averages.first)
        XCTAssertEqual(groceries.category, .groceries)
        XCTAssertEqual(groceries.averagePerMonth, 200, accuracy: 0.0001)
        if case .up = groceries.trend {
            // Spend increased from Jan ($100) to Feb ($300) — expect an "up" trend.
        } else {
            XCTFail("Expected an upward trend, got \(groceries.trend)")
        }
    }

    func testCategoryAveragesEmptyForNoData() {
        XCTAssertTrue(MerchantAnalytics.categoryAverages([]).isEmpty)
    }

    /// A category is averaged over every month the window covers, not just the
    /// months it appeared in. One $120 charge across a three-month window used
    /// to be reported as "$120/mo".
    func testCategoryAveragesDivideByWindowNotByMonthsPresent() {
        let calendar = Calendar(identifier: .gregorian)
        func month(_ index: Int) -> Date {
            calendar.date(from: DateComponents(year: 2025, month: index, day: 10))!
        }
        let inputs = [
            MerchantAnalytics.Input(title: "Gym", amount: 120, category: .health, date: month(1)),
            MerchantAnalytics.Input(title: "Cafe", amount: 10, category: .food, date: month(1)),
            MerchantAnalytics.Input(title: "Cafe", amount: 10, category: .food, date: month(2)),
            MerchantAnalytics.Input(title: "Cafe", amount: 10, category: .food, date: month(3)),
        ]

        let averages = MerchantAnalytics.categoryAverages(inputs, calendar: calendar)
        let health = try? XCTUnwrap(averages.first { $0.category == .health })
        XCTAssertEqual(health?.averagePerMonth ?? 0, 40, accuracy: 0.001)

        let food = try? XCTUnwrap(averages.first { $0.category == .food })
        XCTAssertEqual(food?.averagePerMonth ?? 0, 10, accuracy: 0.001)
    }

    func testCategoryAveragesIncludeInactiveMonthsBetweenFirstAndLastSpend() {
        let calendar = Calendar(identifier: .gregorian)
        let january = calendar.date(from: DateComponents(year: 2025, month: 1, day: 10))!
        let december = calendar.date(from: DateComponents(year: 2025, month: 12, day: 10))!
        let inputs = [
            MerchantAnalytics.Input(title: "Gym", amount: 120, category: .health, date: january),
            MerchantAnalytics.Input(title: "Cafe", amount: 12, category: .food, date: december),
        ]

        let averages = MerchantAnalytics.categoryAverages(inputs, calendar: calendar)
        let health = try? XCTUnwrap(averages.first { $0.category == .health })
        XCTAssertEqual(health?.averagePerMonth ?? 0, 10, accuracy: 0.001)
    }

    // MARK: - Real descriptor shapes from Charlie's ledger

    private func stats(_ titles: [String]) -> [MerchantAnalytics.MerchantStats] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let inputs = titles.enumerated().map { index, title in
            MerchantAnalytics.Input(
                title: title,
                amount: 10,
                category: MerchantHeuristics.category(for: title) ?? .other,
                date: base.addingTimeInterval(Double(index) * 86_400)
            )
        }
        return MerchantAnalytics.merchantStats(inputs)
    }

    func testGooglePaymentsResolvesToTheBilledService() {
        XCTAssertEqual(MerchantNormalizer.normalize("Google *Webpass"), "Webpass")
        XCTAssertEqual(MerchantNormalizer.normalize("GOOGLE *YouTube"), "Youtube")
        XCTAssertNotEqual(
            MerchantNormalizer.normalize("Google *Webpass"),
            MerchantNormalizer.normalize("GOOGLE *YouTube")
        )
    }

    func testPerChargeReferencesCollapseToTheBrand() {
        for title in ["LIME*1", "LIME*2", "Lime*RIDE S2FQ", "Lime"] {
            XCTAssertEqual(MerchantNormalizer.normalize(title), "Lime", title)
        }
        for title in ["LYFT *Priority", "LYFT   *2 RIDES 11-13", "Lyft"] {
            XCTAssertEqual(MerchantNormalizer.normalize(title), "Lyft", title)
        }
    }

    func testProcessorPrefixesResolveToTheRealMerchant() {
        XCTAssertEqual(MerchantNormalizer.normalize("TST* ROQUETTE"), "Roquette")
        XCTAssertEqual(MerchantNormalizer.normalize("SQ *BENJI's INC"), "Benji's Inc")
    }

    func testStoreNumberAndCitySuffixesFoldIntoTheBareMerchant() {
        let merchants = stats(["Safeway #1993", "SAFEWAY 1993 SEATTLE WA", "Safeway"])
        XCTAssertEqual(merchants.count, 1)
        XCTAssertEqual(merchants.first?.name, "Safeway")
        XCTAssertEqual(merchants.first?.visitCount, 3)

        let roquette = stats(["TST* ROQUETTE", "TST*ROQUETTE - SEATTLE"])
        XCTAssertEqual(roquette.count, 1)
        XCTAssertEqual(roquette.first?.name, "Roquette")
    }

    func testCitySuffixNeverMergesWhenTheBareNameIsAbsent() {
        // Nothing in the ledger is plain "Roquette", so the longer form has to
        // stand on its own rather than be guessed at.
        let merchants = stats(["TST*ROQUETTE - SEATTLE", "TST*ROQUETTE - PORTLAND"])
        XCTAssertEqual(merchants.count, 2)
    }

    func testSubBrandsInADifferentCategoryStaySeparate() {
        XCTAssertEqual(MerchantNormalizer.normalize("UBER *TRIP"), "Uber")
        XCTAssertEqual(MerchantNormalizer.normalize("UBER *EATS"), "Uber Eats")

        let merchants = stats(["UBER *TRIP", "UBER *EATS"])
        XCTAssertEqual(merchants.count, 2)
        XCTAssertEqual(Set(merchants.map(\.category)), [.transport, .food])
    }

    func testDrillDownFindsEveryTransactionCountedInTheStats() {
        let titles = ["Safeway #1993", "SAFEWAY 1993 SEATTLE WA", "Safeway"]
        guard let merchant = stats(titles).first else { return XCTFail("no merchant") }
        XCTAssertEqual(titles.filter { merchant.matches($0) }.count, merchant.visitCount)
    }

    func testStatementReferencesFoldIntoASharedMerchantIdentity() {
        // Neither descriptor ever appears bare, so the shared prefix has to be
        // derived — this is the utility that renames itself every month.
        let keys = ["Puget Sound Energy Billpay 4471", "Puget Sound Energy Webpay 8832"]
        let canonical = MerchantNormalizer.canonicalKeys(for: keys, policy: .userAsserted)
        XCTAssertEqual(Set(canonical.values), ["Puget Sound Energy"])
    }

    func testSharedPrefixNeverMergesGenuinelyDifferentMerchants() {
        // What differs is a word, not a reference, so these must stay apart.
        let canonical = MerchantNormalizer.canonicalKeys(for: ["Whole Foods", "Whole Earth"])
        XCTAssertEqual(Set(canonical.values), ["Whole Foods", "Whole Earth"])

        // The reference is dropped, but the sub-brand must not fold into "Uber".
        let uber = MerchantNormalizer.canonicalKeys(for: ["Uber Trip 123", "Uber Eats 456"])
        XCTAssertEqual(uber["Uber Eats 456"], "Uber Eats")
    }

    func testMerchantIdentityIgnoresCaseAndAccents() {
        let variants = ["SAFEWAY #1993", "safeway #1993", "SaFeWaY #1993"]
        XCTAssertEqual(Set(variants.map(MerchantNormalizer.normalize)).count, 1)
        XCTAssertEqual(Set(variants.map(MerchantNormalizer.groupingKey)).count, 1)
        XCTAssertEqual(stats(variants).count, 1)

        XCTAssertEqual(
            MerchantNormalizer.normalize("CAFÉ ZOE"),
            MerchantNormalizer.normalize("Cafe Zoe")
        )
        XCTAssertEqual(
            MerchantNormalizer.normalize("tst*roquette"),
            MerchantNormalizer.normalize("TST* ROQUETTE")
        )
        XCTAssertEqual(
            MerchantNormalizer.normalize("lime*7"),
            MerchantNormalizer.normalize("LIME*2")
        )
        XCTAssertEqual(
            MerchantNormalizer.normalize("google *webpass"),
            MerchantNormalizer.normalize("GOOGLE *Webpass")
        )
    }

    func testMixedCaseDescriptorsLandInOneMerchant() {
        let merchants = stats(["UBER *EATS", "uber *eats", "Uber *Eats"])
        XCTAssertEqual(merchants.count, 1)
        XCTAssertEqual(merchants.first?.visitCount, 3)
        XCTAssertTrue(merchants.first?.matches("uBeR *eAtS") ?? false)
    }
}
