import Foundation

/// Peer-to-peer payment rails — Venmo, Zelle, Cash App and friends.
///
/// The platform name says how the money moved, not what it was for: the same
/// "VENMO PAYMENT" is your half of dinner one week and rent the next. Treating
/// the rail as a transfer drops real spending out of the budget silently, so
/// these descriptors stay uncategorized and the user decides.
///
/// The exception is a descriptor that also describes moving your *own* money —
/// cashing a Venmo balance out to your bank really is a transfer.
enum PeerToPeerPayments {
    static let platforms = [
        "venmo", "zelle", "cash app", "cashapp", "paypal", "apple cash", "apple pay cash",
    ]

    /// Words that mean "between my own accounts" rather than "to a person".
    static let selfMovementMarkers = [
        "cashout", "cash out", "cashed out", "withdrawal", "withdraw",
        "deposit", "add money", "add cash", "standard transfer", "instant transfer",
    ]

    static func isPlatform(_ descriptor: String) -> Bool {
        let tokens = MerchantHeuristics.tokens(in: descriptor)
        return platforms.contains { MerchantHeuristics.contains(MerchantHeuristics.tokens(in: $0), in: tokens) }
    }

    static func isSelfMovement(_ descriptor: String) -> Bool {
        let tokens = MerchantHeuristics.tokens(in: descriptor)
        return selfMovementMarkers.contains { MerchantHeuristics.contains(MerchantHeuristics.tokens(in: $0), in: tokens) }
    }

    /// The category a peer-to-peer descriptor should resolve to, or `nil` to
    /// leave it uncategorized.
    ///
    /// Returning `nil` deliberately short-circuits the generic transfer
    /// keywords: a bank rendering a Venmo as "VENMO PAYMENT ACH DEBIT" would
    /// otherwise match "ach debit" and become a transfer through the back door.
    static func category(for descriptor: String) -> SpendCategory? {
        isSelfMovement(descriptor) ? .transfer : nil
    }
}
