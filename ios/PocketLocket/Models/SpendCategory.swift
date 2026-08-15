import SwiftUI

/// Sendable palette values for model output produced away from the main actor.
/// SwiftUI `Color` is materialized only when a view renders the value.
enum AppTint: String, Sendable {
    case blue, brown, gray, green, indigo, mint, orange, pink, purple, red, systemGray, teal

    var color: Color {
        switch self {
        case .blue: .blue
        case .brown: .brown
        case .gray: .gray
        case .green: .green
        case .indigo: .indigo
        case .mint: .mint
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        case .red: .red
        case .systemGray: Color(.systemGray)
        case .teal: .teal
        }
    }
}

/// The app's spend categories. Plaid's `personal_finance_category` values are
/// mapped onto this smaller, friendlier set (see `CategoryMapper`).
enum SpendCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case food
    case groceries
    case shopping
    case housing
    case transport
    case travel
    case entertainment
    case health
    case services
    case fees
    case income
    case transfer
    case other

    var id: String { rawValue }

    /// Income and transfers are money movement, not discretionary spend, so they
    /// are excluded from the spend ring.
    var isSpending: Bool { self != .income && self != .transfer }

    /// A representative Plaid category value, so a manually chosen category
    /// round-trips through `CategoryMapper`.
    var plaidPrimary: String? {
        switch self {
        case .food: return "FOOD_AND_DRINK"
        case .groceries: return "GROCERIES"
        case .shopping: return "GENERAL_MERCHANDISE"
        case .housing: return "RENT_AND_UTILITIES"
        case .transport: return "TRANSPORTATION"
        case .travel: return "TRAVEL"
        case .entertainment: return "ENTERTAINMENT"
        case .health: return "MEDICAL"
        case .services: return "GENERAL_SERVICES"
        case .fees: return "BANK_FEES"
        case .income: return "INCOME"
        case .transfer: return "TRANSFER_OUT"
        case .other: return nil
        }
    }

    var displayName: String {
        switch self {
        case .food: return "Dining Out"
        case .groceries: return "Groceries"
        case .shopping: return "Shopping"
        case .housing: return "Housing & Bills"
        case .transport: return "Transport"
        case .travel: return "Travel"
        case .entertainment: return "Entertainment"
        case .health: return "Health"
        case .services: return "Services"
        case .fees: return "Fees & Loans"
        case .income: return "Income"
        case .transfer: return "Transfers"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .food: return "fork.knife"
        case .groceries: return "cart.fill"
        case .shopping: return "bag.fill"
        case .housing: return "house.fill"
        case .transport: return "car.fill"
        case .travel: return "airplane"
        case .entertainment: return "film.fill"
        case .health: return "cross.case.fill"
        case .services: return "wrench.and.screwdriver.fill"
        case .fees: return "banknote.fill"
        case .income: return "arrow.down.circle.fill"
        case .transfer: return "arrow.left.arrow.right.circle.fill"
        case .other: return "circle.grid.2x2.fill"
        }
    }

    var tint: Color {
        appTint.color
    }

    var appTint: AppTint {
        switch self {
        case .food: .orange
        case .groceries, .income: .green
        case .shopping: .pink
        case .housing: .blue
        case .transport: .teal
        case .travel: .purple
        case .entertainment: .indigo
        case .health: .red
        case .services: .brown
        case .fees: .gray
        case .transfer: .mint
        case .other: .systemGray
        }
    }
}
