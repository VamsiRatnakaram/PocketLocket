import Foundation

/// Maps recognized provider category values onto `SpendCategory`. SimpleFIN does
/// not require a category, but connected institutions may provide one in a
/// transaction's `extra` payload.
enum CategoryMapper {
    static func map(primary: String?, detailed: String? = nil) -> SpendCategory {
        recognizedCategory(primary: primary, detailed: detailed) ?? .other
    }

    /// Returns `nil` for an unknown value so a caller can fall back to merchant
    /// recognition instead of treating a provider's custom label as authoritative.
    static func recognizedCategory(primary: String?, detailed: String? = nil) -> SpendCategory? {
        let key = normalizedKey(detailed).isEmpty ? normalizedKey(primary) : normalizedKey(detailed)

        if key.hasPrefix("FOOD_AND_DRINK") { return .food }
        if key.hasPrefix("GROCER") { return .groceries }
        if key.hasPrefix("GENERAL_MERCHANDISE") { return .shopping }
        if key.hasPrefix("RENT_AND_UTILITIES") { return .housing }
        if key.hasPrefix("TRANSPORTATION") { return .transport }
        if key.hasPrefix("TRAVEL") { return .travel }
        if key.hasPrefix("ENTERTAINMENT") { return .entertainment }
        if key.hasPrefix("MEDICAL") { return .health }
        if key.hasPrefix("GENERAL_SERVICES") { return .services }
        if key.hasPrefix("BANK_FEES") || key.hasPrefix("LOAN_PAYMENTS") { return .fees }
        if key.hasPrefix("INCOME") { return .income }
        if key.hasPrefix("TRANSFER_OUT") { return .transfer }

        switch key {
        case "FOOD", "DINING", "RESTAURANT", "RESTAURANTS", "FAST_FOOD", "COFFEE", "COFFEE_SHOPS", "BARS_AND_NIGHTLIFE":
            return .food
        case "SUPERMARKET", "SUPERMARKETS":
            return .groceries
        case "SHOPPING", "RETAIL", "CLOTHING_AND_ACCESSORIES", "ELECTRONICS", "HOME_GOODS":
            return .shopping
        case "HOUSING", "RENT", "UTILITIES", "UTILITY", "HOME_IMPROVEMENT", "TELECOMMUNICATIONS":
            return .housing
        case "TRANSPORT", "GAS", "GAS_STATIONS", "FUEL", "PARKING", "PUBLIC_TRANSIT", "RIDESHARE":
            return .transport
        case "AIRLINES", "LODGING", "HOTELS", "CAR_RENTAL":
            return .travel
        case "MOVIES_AND_DVDS", "MUSIC_AND_AUDIO", "GAMES":
            return .entertainment
        case "HEALTH", "HEALTHCARE", "PERSONAL_CARE", "PHARMACY":
            return .health
        case "SERVICES", "PERSONAL_SERVICES", "GOVERNMENT_AND_NON_PROFIT":
            return .services
        case "FEES", "LOANS":
            return .fees
        case "TRANSFER_IN", "DEPOSIT", "DEPOSITS":
            return .income
        case "TRANSFER", "TRANSFERS":
            return .transfer
        default:
            return detailed == nil ? nil : recognizedCategory(primary: primary)
        }
    }

    private static func normalizedKey(_ value: String?) -> String {
        (value ?? "")
            .uppercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }
}
