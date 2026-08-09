import Foundation

/// Separates account balances into assets and liabilities for the Accounts
/// summary. Liability balances may be reported with either sign by institutions,
/// so their magnitude is always used.
enum AccountBalanceSummary {
    struct Account {
        let type: String?
        let balance: Double
    }

    struct Totals: Equatable {
        var assets: Double
        var liabilities: Double

        var netWorth: Double { assets - liabilities }
    }

    static func totals(for accounts: [Account]) -> Totals {
        accounts.reduce(into: Totals(assets: 0, liabilities: 0)) { totals, account in
            if isLiability(account.type) || account.balance < 0 {
                totals.liabilities += abs(account.balance)
            } else {
                totals.assets += account.balance
            }
        }
    }

    private static func isLiability(_ type: String?) -> Bool {
        switch type?.lowercased() {
        case "credit", "loan", "line_of_credit": return true
        default: return false
        }
    }
}