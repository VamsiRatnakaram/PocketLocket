import Foundation

/// One category row as a widget renders it.
///
/// Carries *both* representations the widget can show: a share of the month's
/// spend (always safe to expose on a Lock Screen) and the dollar amount (only
/// present when the user has opted into amounts).
struct WidgetCategory: Codable, Equatable, Identifiable, Sendable {
    let category: SpendCategory
    /// Dollars spent. `nil` when amounts are hidden, and the encoder omits the
    /// key entirely — the number is not merely unrendered, it is absent.
    let amount: Double?
    /// Share of total spend, 0...1. Used for the bar and for the Lock Screen
    /// row, where a percentage says enough without revealing a balance.
    let share: Double

    var id: String { category.id }
}

/// What the widgets draw.
///
/// A snapshot of the *derivation*, not of the ledger: the app already computes
/// all of this for the Home screen, and the widget re-renders the result. It
/// carries no transaction rows, no merchant names, no account ids, and no
/// credentials — there is nothing in here that would be worth stealing beyond
/// what the user chose to put on their own Home Screen.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Bumped only on a breaking shape change. Decoders accept any earlier
    /// version by ignoring unknown keys, so an older widget reading a newer
    /// file (or the reverse, across an app update) degrades to "no data"
    /// instead of crashing or drawing nonsense.
    static let schemaVersion = 1

    let schemaVersion: Int
    /// Start of the month being shown, so a widget can say "March" rather than
    /// assuming today's month is the one on screen.
    let monthStart: Date
    /// The month's spend, in the currency the transactions were recorded in.
    let totalSpent: Double
    let monthlyBudget: Double
    /// Largest first, already trimmed to fit the largest widget.
    let categories: [WidgetCategory]
    /// `totalSpent / monthlyBudget`, unclamped — over budget reads as 1.28 and
    /// the view decides how to draw the second lap. Nil when no budget is set.
    let fraction: Double?
    let safeToSpend: Double?
    let isoCurrencyCode: String
    /// Whether dollar values are in this snapshot at all. Redundant with the
    /// per-category nils, but it lets the widget tell "you have no budget"
    /// apart from "you hid the numbers" without guessing.
    let showsAmounts: Bool
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case monthStart
        case totalSpent
        case monthlyBudget
        case categories
        case fraction
        case safeToSpend
        case isoCurrencyCode
        case showsAmounts
        case updatedAt
    }

    var isOverBudget: Bool {
        monthlyBudget > 0 && totalSpent > monthlyBudget
    }

    /// Dollars left; negative when over budget, mirroring `HomeViewModel`.
    var remaining: Double { monthlyBudget - totalSpent }

    var hasBudget: Bool { monthlyBudget > 0 }

    /// How long ago the app last wrote this. The widget cannot refresh itself on
    /// a schedule the app controls, so an honest timestamp is the only way to
    /// tell "up to date" from "as of your last unlock".
    func ageInMinutes(now: Date = Date()) -> Int {
        max(0, Int(now.timeIntervalSince(updatedAt) / 60))
    }

    /// Past this, the widget labels itself stale rather than presenting the
    /// figure as current. Generous on purpose: a widget that nags every hour is
    /// worse than one that quietly admits it is a day old.
    ///
    /// Inclusive, so a timeline entry scheduled exactly at the threshold reads
    /// as stale — with a strict `>` the flip entry would render one more minute
    /// of the fresh caption before correcting itself.
    func isStale(now: Date = Date()) -> Bool {
        ageInMinutes(now: now) >= Self.staleAfterMinutes
    }

    static let staleAfterMinutes = 360

    // MARK: - Reading

    /// Decodes the published snapshot, or `nil` when there is nothing usable:
    /// no file yet, a payload from a future schema, or a truncated write.
    static func load(from defaults: UserDefaults = AppGroup.defaults) -> WidgetSnapshot? {
        guard let raw = defaults.data(forKey: WidgetSnapshotStore.key) else { return nil }
        // Dates are left to the default strategy, which stores a `Date` as its
        // reference-date double: lossless, and no format to get out of step
        // between the two binaries.
        guard let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: raw) else { return nil }
        return snapshot.schemaVersion == schemaVersion ? snapshot : nil
    }

    // MARK: - Building

    /// Builds the widget's payload from the month's already-resolved spend items.
    ///
    /// - Parameter categoryBudgets: per-category limits, used only to mark a row
    ///   red when that category is over its own limit. Passing an empty map is
    ///   fine; the rows simply carry no verdict.
    /// - Parameter showsAmounts: when false, no dollar value is written for the
    ///   categories. `totalSpent`/`monthlyBudget` stay, because the ring and the
    ///   percentage are derived from them and stripping them would leave the
    ///   widget with nothing to draw — but they are ratios on screen, never
    ///   dollars, so a Lock Screen reader sees "62%" and "Dining Out".
    static func build(
        items: [SpendItem],
        monthlyBudget: Double,
        monthStart: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        categoryBudgets: [SpendCategory: Double] = [:],
        safeToSpendFocus: Set<SpendCategory> = [],
        isoCurrencyCode: String = "USD",
        showsAmounts: Bool = false,
        maxCategories: Int = 6
    ) -> WidgetSnapshot {
        let spends = SpendAggregator.totals(items)
        let totalSpent = SpendAggregator.totalSpend(spends)
        let fraction = monthlyBudget > 0 ? totalSpent / monthlyBudget : nil

        let basis = SafeToSpendBasis.resolve(
            items: items,
            monthlyBudget: monthlyBudget,
            categoryBudgets: categoryBudgets,
            focus: safeToSpendFocus,
            calendar: calendar,
            now: now
        )

        let categories = spends.prefix(max(maxCategories, 0)).map { spend in
            WidgetCategory(
                category: spend.category,
                amount: showsAmounts ? spend.amount : nil,
                share: totalSpent > 0 ? spend.amount / totalSpent : 0
            )
        }

        return WidgetSnapshot(
            schemaVersion: schemaVersion,
            monthStart: monthStart,
            totalSpent: totalSpent,
            monthlyBudget: monthlyBudget,
            categories: Array(categories),
            fraction: fraction,
            safeToSpend: basis?.dailyAllowance(
                daysLeft: MonthlyPace.daysLeftInMonth(for: now, calendar: calendar)
            ),
            isoCurrencyCode: isoCurrencyCode,
            showsAmounts: showsAmounts,
            updatedAt: now
        )
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }
}
