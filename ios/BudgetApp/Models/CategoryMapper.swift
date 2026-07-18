import Foundation

/// Maps Plaid `personal_finance_category.primary` values onto `SpendCategory`.
/// Pure and side-effect free so it is easy to unit test.
enum CategoryMapper {
    static func map(primary: String?, detailed: String? = nil) -> SpendCategory {
        switch (primary ?? "").uppercased() {
        case "FOOD_AND_DRINK":
            return .food
        case "GROCERIES":
            return .groceries
        case "GENERAL_MERCHANDISE":
            return .shopping
        case "RENT_AND_UTILITIES", "HOME_IMPROVEMENT":
            return .housing
        case "TRANSPORTATION":
            return .transport
        case "TRAVEL":
            return .travel
        case "ENTERTAINMENT":
            return .entertainment
        case "MEDICAL", "PERSONAL_CARE":
            return .health
        case "GENERAL_SERVICES", "GOVERNMENT_AND_NON_PROFIT":
            return .services
        case "BANK_FEES", "LOAN_PAYMENTS":
            return .fees
        case "INCOME", "TRANSFER_IN":
            return .income
        case "TRANSFER_OUT":
            return .transfer
        default:
            return .other
        }
    }
}
