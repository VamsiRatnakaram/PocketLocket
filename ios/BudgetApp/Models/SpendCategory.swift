import SwiftUI

/// The app's spend categories. Plaid's `personal_finance_category` values are
/// mapped onto this smaller, friendlier set (see `CategoryMapper`).
enum SpendCategory: String, CaseIterable, Identifiable, Codable {
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
        switch self {
        case .food: return .orange
        case .groceries: return .green
        case .shopping: return .pink
        case .housing: return .blue
        case .transport: return .teal
        case .travel: return .purple
        case .entertainment: return .indigo
        case .health: return .red
        case .services: return .brown
        case .fees: return .gray
        case .income: return .green
        case .transfer: return .mint
        case .other: return Color(.systemGray)
        }
    }
}
