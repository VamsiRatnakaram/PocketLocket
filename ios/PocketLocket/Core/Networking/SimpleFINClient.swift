import Foundation

// MARK: - SimpleFIN response shapes (https://www.simplefin.org/protocol.html)

struct SFAccountSet: Decodable {
    let accounts: [SFAccount]
    let errors: [String]

    enum CodingKeys: String, CodingKey { case accounts, errors }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accounts = (try? container.decode([SFAccount].self, forKey: .accounts)) ?? []
        errors = (try? container.decode([String].self, forKey: .errors)) ?? []
    }
}

struct SFAccount: Decodable {
    let id: String
    let name: String?
    let currency: String?
    let balance: String?
    let balanceDate: Double?
    let transactions: [SFTxn]?

    enum CodingKeys: String, CodingKey {
        case id, name, currency, balance
        case balanceDate = "balance-date"
        case transactions
    }
}

struct SFTxn: Decodable {
    let id: String
    let posted: Double?
    let amount: String
    let description: String?
    let pending: Bool?
    let category: String?

    enum CodingKeys: String, CodingKey { case id, posted, amount, description, pending, extra }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        posted = try? container.decode(Double.self, forKey: .posted)
        // SimpleFIN sends amount as a decimal string, but tolerate a JSON number too.
        if let string = try? container.decode(String.self, forKey: .amount) {
            amount = string
        } else if let number = try? container.decode(Double.self, forKey: .amount) {
            amount = String(number)
        } else {
            amount = "0"
        }
        description = try? container.decode(String.self, forKey: .description)
        pending = try? container.decode(Bool.self, forKey: .pending)
        category = (try? container.decode(SFTxnExtra.self, forKey: .extra))?.category
    }
}

private struct SFTxnExtra: Decodable {
    let category: String?
}

/// Pure helpers (unit-testable).
enum SimpleFINMapper {
    /// SimpleFIN: positive amount = money in. App convention: positive = spend.
    static func appAmount(from simpleFINAmount: String) -> Double {
        -(Double(simpleFINAmount) ?? 0)
    }

    static func inferType(name: String?) -> String {
        let lower = (name ?? "").lowercased()
        if lower.contains("credit") || lower.contains("card") || lower.contains("amex")
            || lower.contains("visa") || lower.contains("mastercard") {
            return "credit"
        }
        if lower.contains("loan") || lower.contains("mortgage") || lower.contains("heloc")
            || lower.contains("line of credit") || lower.contains("auto finance") {
            return "loan"
        }
        return "depository"
    }
}

/// Talks to a SimpleFIN Bridge directly from the device (read-only). No backend
/// is involved: the access URL (a credential) is stored in the Keychain and used
/// with HTTP Basic Auth. All requests are HTTPS.
struct SimpleFINClient {
    enum SFError: LocalizedError {
        case invalidToken
        case invalidAccessURL
        case claimFailed(Int)
        case fetchFailed(Int, String?)
        case server(String)

        var errorDescription: String? {
            switch self {
            case .invalidToken: return "That doesn't look like a valid setup token."
            case .invalidAccessURL: return "The saved SimpleFIN connection looks invalid. Reconnect SimpleFIN in Settings."
            case let .claimFailed(code): return "Couldn't claim the token (HTTP \(code)). It may already be used."
            case let .fetchFailed(code, message):
                if let message, !message.isEmpty { return "SimpleFIN request failed (HTTP \(code)): \(message)" }
                return "SimpleFIN request failed (HTTP \(code))."
            case let .server(message): return "SimpleFIN: \(message)"
            }
        }
    }

    /// Exchanges a one-time setup token for a long-lived access URL.
    func claim(setupToken: String) async throws -> String {
        let trimmed = setupToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let decoded = Data(base64Encoded: trimmed),
            let claimURLString = String(data: decoded, encoding: .utf8),
            let claimURL = URL(string: claimURLString)
        else { throw SFError.invalidToken }

        var request = URLRequest(url: claimURL)
        request.httpMethod = "POST"
        request.setValue("0", forHTTPHeaderField: "Content-Length")

        let (body, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else { throw SFError.claimFailed(status) }

        let accessURL = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard accessURL.hasPrefix("http") else { throw SFError.claimFailed(status) }
        return accessURL
    }

    /// Fetches accounts + transactions (optionally limited to `since`).
    func fetchAccounts(accessURL: String, since: Date? = nil) async throws -> SFAccountSet {
        guard
            let comps = URLComponents(string: accessURL),
            let scheme = comps.scheme,
            let host = comps.host,
            let user = comps.user
        else { throw SFError.invalidAccessURL }
        let password = comps.password ?? ""

        var endpoint = URLComponents()
        endpoint.scheme = scheme
        endpoint.host = host
        endpoint.port = comps.port
        endpoint.path = comps.path + "/accounts"
        var query = [URLQueryItem(name: "version", value: "2")]
        if let since {
            query.append(URLQueryItem(name: "start-date", value: String(Int(since.timeIntervalSince1970))))
        }
        endpoint.queryItems = query

        guard let url = endpoint.url else { throw SFError.invalidAccessURL }

        var request = URLRequest(url: url)
        let credential = Data("\(user):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(credential)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            let snippet = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(200)
            throw SFError.fetchFailed(status, snippet.isEmpty ? nil : String(snippet))
        }

        let result: SFAccountSet
        do {
            result = try JSONDecoder().decode(SFAccountSet.self, from: data)
        } catch {
            throw SFError.server("Received an unexpected response from the bridge.")
        }
        // SimpleFIN reports per-connection problems in `errors` (e.g. a bank that
        // needs re-auth) while still returning 200. Surface them if nothing came back.
        if result.accounts.isEmpty, !result.errors.isEmpty {
            throw SFError.server(result.errors.joined(separator: " "))
        }
        return result
    }
}
