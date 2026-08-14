import Foundation

/// Normalizes a merchant/transaction title into a stable grouping key, so
/// "STARBUCKS #4521", "Starbucks 04521 Seattle WA", and "SQ *STARBUCKS" all
/// roll up into a single merchant for frequency/trend analysis.
enum MerchantNormalizer {
    /// Payment processors and marketplaces that put *their* name in front of a
    /// star and the merchant you actually paid behind it, so the useful half of
    /// "SQ *BLUE BOTTLE" is the second half.
    ///
    /// Any other name before a star is the merchant itself, with a
    /// per-transaction reference behind it — see `stripStarSuffix`.
    private static let processorPrefixes = [
        "sq", "sqc", "tst", "pp", "paypal", "pyp", "sp", "wl", "wpy", "ebay", "stripe", "shopify",
        // Google Payments bills on behalf of whatever you actually subscribed
        // to — "GOOGLE *Webpass" is an ISP, "GOOGLE *YouTube" is streaming.
        // Without this they'd all collapse into one "Google" merchant spanning
        // three unrelated categories.
        "google"
    ]

    /// Real USPS state/territory codes only — deliberately not "any 2-letter
    /// token" so short legitimate merchant-name words aren't mistaken for a
    /// state suffix and stripped (which would otherwise merge distinct
    /// merchants under one normalized key).
    private static let usStateAbbreviations = [
        "al", "ak", "az", "ar", "ca", "co", "ct", "de", "fl", "ga",
        "hi", "id", "il", "in", "ia", "ks", "ky", "la", "me", "md",
        "ma", "mi", "mn", "ms", "mo", "mt", "ne", "nv", "nh", "nj",
        "nm", "ny", "nc", "nd", "oh", "ok", "or", "pa", "ri", "sc",
        "sd", "tn", "tx", "ut", "vt", "va", "wa", "wv", "wi", "wy",
        "dc", "pr"
    ].joined(separator: "|")

    /// Normalization is regex-heavy and the same merchant strings recur across
    /// hundreds of transactions and every recomputation, so results are
    /// memoized by raw title. The mapping is a pure function of its input, so
    /// entries can never go stale.
    private static let cacheLock = NSLock()
    private static var cache: [String: String] = [:]

    static func normalize(_ raw: String) -> String {
        stripReferences(groupingKey(raw))
    }

    /// The same identity as `normalize`, but with store numbers and statement
    /// references left on.
    ///
    /// `canonicalKeys` needs to see them: they are the evidence that two
    /// descriptors differ only by a per-charge reference rather than by being
    /// different businesses. Strip them first and "… BILLPAY 4471" / "… WEBPAY
    /// 8832" become indistinguishable from "Whole Foods" / "Whole Earth".
    static func groupingKey(_ raw: String) -> String {
        cacheLock.lock()
        let cached = cache[raw]
        cacheLock.unlock()
        if let cached { return cached }

        let result = computeNormalized(raw)
        cacheLock.lock()
        if cache.count > 5000 { cache.removeAll(keepingCapacity: true) }
        cache[raw] = result
        cacheLock.unlock()
        return result
    }

    /// Drops a trailing "#1234" / bare store-number token.
    private static func stripReferences(_ value: String) -> String {
        var result = value.replacingOccurrences(
            of: #"\s*#\s*\d+\s*$"#, with: "", options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\s+\d{3,6}\s*$"#, with: "", options: .regularExpression
        )
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? value : result
    }

    /// Resolves a descriptor built around "*" down to the merchant itself.
    ///
    /// Acquirers put their own name first ("SQ *BLUE BOTTLE"), so the merchant
    /// is what follows. Everyone else puts the merchant first and a
    /// per-transaction reference after it — "LIME*1", "LIME*2", "AMZN
    /// Mktp US*2H4KJ", "UBER *TRIP" — and that reference is different on every
    /// single charge, which is exactly what was splitting one merchant into
    /// dozens of one-visit entries.
    private static func resolveStarSegments(_ value: String) -> String {
        guard value.contains("*") else { return value }

        let segments = value
            .split(separator: "*", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = segments.first else { return value }

        // A leading star is the processor form with the processor missing, so
        // the merchant is still what follows it.
        if first.isEmpty || processorPrefixes.contains(first) {
            // Keep everything past the processor: "sq *blue bottle *2" is Blue
            // Bottle, not "2".
            let remainder = segments.dropFirst().joined(separator: " ")
            let trimmed = remainder.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? value : resolveStarSegments(trimmed)
        }

        // Don't throw the descriptor away when the half in front of the star is
        // too short to identify a merchant on its own.
        guard first.count >= 3 else { return value }

        // "UBER *EATS" is a genuinely different business from "UBER *TRIP",
        // while "LIME*1" and "LYFT *Priority" are one business with a
        // per-charge reference stuck on the end. Rather than keep a list of
        // brands that have real sub-brands, ask the curated category table:
        // keep the suffix only when brand + suffix is recognized as its own
        // merchant in a *different* category than the brand alone.
        let remainder = segments.dropFirst()
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if !remainder.isEmpty {
            let combined = "\(first) \(remainder)"
            if let combinedCategory = MerchantHeuristics.category(for: combined),
               combinedCategory != MerchantHeuristics.category(for: first) {
                return combined
            }
        }
        return first
    }

    /// Collapses normalized keys that are merely a longer form of the same
    /// merchant: "Safeway 1993 Seattle" folds into "Safeway", and
    /// "Puget Sound Energy Billpay 4471" / "… Webpay 8832" both fold into
    /// "Puget Sound Energy".
    ///
    /// This is what finally strips store numbers, statement references, and
    /// city suffixes without needing a list of city names. Extra tokens are
    /// dropped only when either the barer name already appears in the user's
    /// own history, or two descriptors differ solely by something that looks
    /// like a per-charge reference — so "Whole Foods" and "Whole Earth" are
    /// never merged into "Whole". A shared prefix is also refused whenever the
    /// two forms carry different known categories, keeping "Uber Eats" out of
    /// "Uber".
    static func canonicalKeys(for keys: some Sequence<String>) -> [String: String] {
        // A shorter form always shares its first token with the longer one, so
        // bucketing by that token keeps the pairwise scan below linear overall
        // instead of quadratic across the whole ledger.
        var buckets: [String: [(key: String, words: [String], tokens: [String])]] = [:]
        for key in Set(keys) {
            let words = key.split(separator: " ").map(String.init)
            let tokens = words.map { $0.lowercased() }
            guard let first = tokens.first else { continue }
            buckets[first, default: []].append((key, words, tokens))
        }

        var mapping: [String: String] = [:]
        for entries in buckets.values {
            var candidates = entries.map { (name: $0.key, tokens: $0.tokens) }

            for i in entries.indices {
                for j in entries.index(after: i)..<entries.endIndex {
                    let (a, b) = (entries[i], entries[j])
                    let shared = zip(a.tokens, b.tokens).prefix { $0 == $1 }.count
                    guard shared > 0, shared < a.tokens.count, shared < b.tokens.count,
                          looksLikeReference(a.tokens.dropFirst(shared)),
                          looksLikeReference(b.tokens.dropFirst(shared)) else { continue }
                    candidates.append((
                        name: a.words.prefix(shared).joined(separator: " "),
                        tokens: Array(a.tokens.prefix(shared))
                    ))
                }
            }

            // Shortest first, so a key folds into the barest form available.
            let byLength = candidates.sorted { $0.tokens.count < $1.tokens.count }
            for entry in entries {
                var canonical = entry.key
                for candidate in byLength where candidate.tokens.count < entry.tokens.count {
                    guard entry.tokens.starts(with: candidate.tokens),
                          categoriesAgree(candidate.name, entry.key) else { continue }
                    canonical = candidate.name
                    break
                }
                mapping[entry.key] = stripReferences(canonical)
            }
        }
        return mapping
    }

    /// Whether the tokens a merchant name would lose look like a per-charge or
    /// per-statement reference rather than a different business.
    private static func looksLikeReference(_ tokens: some Sequence<String>) -> Bool {
        tokens.contains { $0.contains(where: \.isNumber) }
    }

    /// Two forms may only be merged when they don't resolve to *different*
    /// known categories — "Uber Eats" must not fold into "Uber".
    private static func categoriesAgree(_ shorter: String, _ longer: String) -> Bool {
        guard let short = MerchantHeuristics.category(for: shorter),
              let long = MerchantHeuristics.category(for: longer) else { return true }
        return short == long
    }

    private static func computeNormalized(_ raw: String) -> String {
        var value = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return raw }

        value = resolveStarSegments(value)

        // Drop trailing "city, ST" / "city ST" location suffixes — restricted
        // to real US state/territory codes (rather than any 2-letter word) so
        // legitimate short merchant names/tokens aren't mistaken for a state
        // and stripped, which would otherwise merge distinct merchants.
        if value.split(separator: " ").count > 1 {
            value = value.replacingOccurrences(
                of: #"\s+(\#(Self.usStateAbbreviations))\s*$"#, with: "", options: [.regularExpression, .caseInsensitive]
            )
        }

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
        /// No prior-period spend to compare against (e.g. a merchant's first
        /// visit falls in the recent half of the window) — distinct from
        /// `.up`/`.down` since there's no real percentage change to report.
        case new
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
        /// Every normalized descriptor folded into this merchant, so drill-downs
        /// can find the same transactions the stats were built from.
        let aliases: Set<String>
        var id: String { name }

        func matches(_ title: String) -> Bool {
            aliases.contains(MerchantNormalizer.groupingKey(title))
                || MerchantNormalizer.normalize(title) == name
        }
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
        var aliases: [String: Set<String>] = [:]
        let canonical = MerchantNormalizer.canonicalKeys(
            for: spending.map { MerchantNormalizer.groupingKey($0.title) }
        )
        for item in spending {
            let grouping = MerchantNormalizer.groupingKey(item.title)
            let key = canonical[grouping] ?? MerchantNormalizer.normalize(item.title)
            grouped[key, default: []].append(item)
            aliases[key, default: []].insert(grouping)
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
                trend: trend(current: recent, previous: earlier),
                aliases: aliases[name] ?? [name]
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
    /// - Parameter stats: Pre-computed `merchantStats(inputs)` for the same
    ///   inputs, if the caller already has it — avoids a redundant O(n)
    ///   grouping pass. When `nil` it is computed here.
    static func recurringMerchants(
        _ inputs: [Input],
        minMonths: Int = 3,
        calendar: Calendar = .current,
        stats: [MerchantStats]? = nil
    ) -> [MerchantStats] {
        let spending = spendingOnly(inputs)
        var monthsByMerchant: [String: Set<DateComponents>] = [:]
        let canonical = MerchantNormalizer.canonicalKeys(
            for: spending.map { MerchantNormalizer.groupingKey($0.title) }
        )
        for item in spending {
            let grouping = MerchantNormalizer.groupingKey(item.title)
            let key = canonical[grouping] ?? MerchantNormalizer.normalize(item.title)
            let comps = calendar.dateComponents([.year, .month], from: item.date)
            monthsByMerchant[key, default: []].insert(comps)
        }
        let qualifying = Set(monthsByMerchant.filter { $0.value.count >= minMonths }.keys)
        let resolved = stats ?? merchantStats(inputs, calendar: calendar)
        return resolved.filter { qualifying.contains($0.name) }
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

        // Every month the window actually covers, not just the months a given
        // category appeared in. Dividing a category's total by its *present*
        // months reported a single $120 charge in a year as "$120/mo", and
        // left a category that stopped entirely looking flat instead of down.
        guard let firstMonth = monthly.first?.monthStart,
              let lastMonth = monthly.last?.monthStart
        else { return [] }
        var windowMonths: [Date] = []
        var month = firstMonth
        while month <= lastMonth {
            windowMonths.append(month)
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }

        var byCategory: [SpendCategory: [Date: Double]] = [:]
        for entry in monthly { byCategory[entry.category, default: [:]][entry.monthStart] = entry.amount }

        return byCategory.map { category, amounts in
            let series = windowMonths.map { amounts[$0] ?? 0 }
            let total = series.reduce(0, +)
            let average = total / Double(series.count)

            let midIndex = series.count / 2
            let earlierHalf = Array(series.prefix(midIndex))
            let recentHalf = Array(series.suffix(series.count - midIndex))
            let earlierAvg = earlierHalf.isEmpty ? 0 : earlierHalf.reduce(0, +) / Double(earlierHalf.count)
            let recentAvg = recentHalf.isEmpty ? 0 : recentHalf.reduce(0, +) / Double(recentHalf.count)

            return CategoryAverage(
                category: category,
                averagePerMonth: average,
                trend: series.count >= 2 ? trend(current: recentAvg, previous: earlierAvg) : .flat
            )
        }
        .sorted { $0.averagePerMonth > $1.averagePerMonth }
    }

    private static func trend(current: Double, previous: Double) -> Trend {
        guard previous > 0.01 else { return current > 0.01 ? .new : .flat }
        let change = (current - previous) / previous
        if abs(change) < 0.05 { return .flat }
        return change > 0 ? .up(percent: change * 100) : .down(percent: -change * 100)
    }
}
