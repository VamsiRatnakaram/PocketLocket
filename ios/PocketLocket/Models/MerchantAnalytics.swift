import Foundation

/// Normalizes a merchant/transaction title into a stable grouping key, so
/// "STARBUCKS #4521", "Starbucks 04521 Seattle WA", and "SQ *STARBUCKS" all
/// roll up into a single merchant for frequency/trend analysis.
enum MerchantNormalizer {
    /// Trailing store numbers, POS prefixes, and location noise to strip so
    /// repeat visits to the same chain are recognized as one merchant.
    private static let posPrefixes = ["sq *", "sq*", "tst*", "tst *", "pp*", "pp *"]

    static func normalize(_ raw: String) -> String {
        var value = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return raw }

        for prefix in posPrefixes where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }

        // Drop a trailing "#1234" / "no. 1234" / bare store-number token.
        value = value.replacingOccurrences(
            of: #"\s*#\s*\d+\s*$"#, with: "", options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\s+\d{3,6}\s*$"#, with: "", options: .regularExpression
        )

        // Drop trailing "city, ST" / "city ST" location suffixes (two-letter state).
        value = value.replacingOccurrences(
            of: #"\s+[a-z]{2}\s*$"#, with: "", options: .regularExpression
        )

        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return raw.trimmingCharacters(in: .whitespacesAndNewlines) }

        return value
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

/// Pure, testable trend-mining over transaction history — merchant frequency,
/// spend habits, and category trajectories. The UI feeds in plain `Input`s
/// built from `TransactionRecord`s; nothing here touches SwiftData/SwiftUI.
enum MerchantAnalytics {
    struct Input {
        let title: String
        let amount: Double
        let category: SpendCategory
        let date: Date
    }

    enum Trend: Hashable {
        case up(percent: Double)
        case down(percent: Double)
        case flat
    }

    struct MerchantStats: Identifiable, Hashable {
        let name: String
        let category: SpendCategory
        let visitCount: Int
        let totalSpent: Double
        let averagePerVisit: Double
        let firstDate: Date
        let lastDate: Date
        let trend: Trend
        var id: String { name }
    }

    struct CategoryMonth: Identifiable {
        let category: SpendCategory
        let monthStart: Date
        let amount: Double
        var id: String { "\(category.rawValue)-\(monthStart.timeIntervalSince1970)" }
    }

    struct CategoryAverage: Identifiable {
        let category: SpendCategory
        let averagePerMonth: Double
        let trend: Trend
        var id: String { category.rawValue }
    }

    /// Only positive-amount, spending-category transactions count toward
    /// merchant/category mining (matches SpendAggregator's convention).
    private static func spendingOnly(_ inputs: [Input]) -> [Input] {
        inputs.filter { $0.category.isSpending && $0.amount > 0 }
    }

    /// Per-merchant visit counts, totals, and trend vs. the prior period of
    /// equal length immediately preceding it.
    static func merchantStats(_ inputs: [Input], calendar: Calendar = .current) -> [MerchantStats] {
        let spending = spendingOnly(inputs)
        guard !spending.isEmpty else { return [] }

        let sortedDates = spending.map(\.date).sorted()
        guard let earliest = sortedDates.first, let latest = sortedDates.last else { return [] }
        let midpoint = earliest.addingTimeInterval(latest.timeIntervalSince(earliest) / 2)

        var grouped: [String: [Input]] = [:]
        for item in spending {
            grouped[MerchantNormalizer.normalize(item.title), default: []].append(item)
        }

        return grouped.map { name, items in
            let total = items.reduce(0) { $0 + $1.amount }
            let dates = items.map(\.date)
            // Most common category among this merchant's transactions.
            let category = items
                .reduce(into: [SpendCategory: Int]()) { $0[$1.category, default: 0] += 1 }
                .max { $0.value < $1.value }?.key ?? items[0].category

            let recent = items.filter { $0.date >= midpoint }.reduce(0) { $0 + $1.amount }
            let earlier = items.filter { $0.date < midpoint }.reduce(0) { $0 + $1.amount }

            return MerchantStats(
                name: name,
                category: category,
                visitCount: items.count,
                totalSpent: total,
                averagePerVisit: total / Double(items.count),
                firstDate: dates.min() ?? earliest,
                lastDate: dates.max() ?? latest,
                trend: trend(current: recent, previous: earlier)
            )
        }
        .sorted { $0.totalSpent > $1.totalSpent }
    }

    static func topByFrequency(_ stats: [MerchantStats], limit: Int = 10) -> [MerchantStats] {
        stats.sorted { $0.visitCount > $1.visitCount }.prefix(limit).map { $0 }
    }

    static func topBySpend(_ stats: [MerchantStats], limit: Int = 10) -> [MerchantStats] {
        stats.sorted { $0.totalSpent > $1.totalSpent }.prefix(limit).map { $0 }
    }

    /// Merchants that recur in at least `minMonths` distinct calendar months —
    /// a signal for habitual spend (recurring coffee run, weekly groceries, a
    /// subscription-like pattern) as opposed to a one-off purchase.
    static func recurringMerchants(_ inputs: [Input], minMonths: Int = 3, calendar: Calendar = .current) -> [MerchantStats] {
        let spending = spendingOnly(inputs)
        var monthsByMerchant: [String: Set<DateComponents>] = [:]
        for item in spending {
            let key = MerchantNormalizer.normalize(item.title)
            let comps = calendar.dateComponents([.year, .month], from: item.date)
            monthsByMerchant[key, default: []].insert(comps)
        }
        let qualifying = Set(monthsByMerchant.filter { $0.value.count >= minMonths }.keys)
        return merchantStats(inputs, calendar: calendar).filter { qualifying.contains($0.name) }
    }

    /// Per-category, per-calendar-month totals over the supplied transactions —
    /// feeds a trend chart (e.g. "average grocery spend" over time).
    static func categoryMonthlyTotals(_ inputs: [Input], calendar: Calendar = .current) -> [CategoryMonth] {
        let spending = spendingOnly(inputs)
        var buckets: [SpendCategory: [Date: Double]] = [:]
        for item in spending {
            guard let monthStart = calendar.dateInterval(of: .month, for: item.date)?.start else { continue }
            buckets[item.category, default: [:]][monthStart, default: 0] += item.amount
        }
        return buckets.flatMap { category, months in
            months.map { CategoryMonth(category: category, monthStart: $0.key, amount: $0.value) }
        }
        .sorted { $0.monthStart < $1.monthStart }
    }

    /// Average monthly spend per category plus a trend (recent half of the
    /// window vs. earlier half), e.g. "Groceries: avg $412/mo, trending down".
    static func categoryAverages(_ inputs: [Input], calendar: Calendar = .current) -> [CategoryAverage] {
        let monthly = categoryMonthlyTotals(inputs, calendar: calendar)
        guard !monthly.isEmpty else { return [] }

        var byCategory: [SpendCategory: [CategoryMonth]] = [:]
        for entry in monthly { byCategory[entry.category, default: []].append(entry) }

        return byCategory.map { category, entries in
            let sorted = entries.sorted { $0.monthStart < $1.monthStart }
            let total = sorted.reduce(0) { $0 + $1.amount }
            let average = total / Double(sorted.count)

            let midIndex = sorted.count / 2
            let earlierHalf = Array(sorted.prefix(midIndex))
            let recentHalf = Array(sorted.suffix(sorted.count - midIndex))
            let earlierAvg = earlierHalf.isEmpty ? 0 : earlierHalf.reduce(0) { $0 + $1.amount } / Double(earlierHalf.count)
            let recentAvg = recentHalf.isEmpty ? 0 : recentHalf.reduce(0) { $0 + $1.amount } / Double(recentHalf.count)

            return CategoryAverage(
                category: category,
                averagePerMonth: average,
                trend: sorted.count >= 2 ? trend(current: recentAvg, previous: earlierAvg) : .flat
            )
        }
        .sorted { $0.averagePerMonth > $1.averagePerMonth }
    }

    private static func trend(current: Double, previous: Double) -> Trend {
        guard previous > 0.01 else { return current > 0.01 ? .up(percent: 100) : .flat }
        let change = (current - previous) / previous
        if abs(change) < 0.05 { return .flat }
        return change > 0 ? .up(percent: change * 100) : .down(percent: -change * 100)
    }
}
