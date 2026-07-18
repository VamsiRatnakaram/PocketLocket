import Foundation
import LocalAuthentication

/// Stores the SimpleFIN access URL (a bank credential) in the Keychain, bound to
/// Face ID / passcode so it can't be read or modified without authentication.
enum SimpleFINStore {
    private static let key = "simplefin_access_url"
    private static var cached: String?

    static func save(_ accessURL: String) {
        cached = accessURL
        guard let data = accessURL.data(using: .utf8) else { return }
        do {
            try KeychainStore.setProtected(data, for: key)
        } catch {
            // A device with no passcode can't use access control; store normally.
            try? KeychainStore.set(data, for: key)
        }
    }

    /// Reads the access URL. Requires Face ID / passcode the first time each
    /// session (reused from the app unlock when possible), then cached in memory.
    static func accessURL(context: LAContext? = nil) -> String? {
        if let cached { return cached }
        guard
            let data = try? KeychainStore.getProtected(key, reason: "Unlock your bank connection", context: context),
            let url = String(data: data, encoding: .utf8)
        else { return nil }
        cached = url
        return url
    }

    /// Presence check that never prompts for authentication.
    static var isConnected: Bool { cached != nil || KeychainStore.exists(key) }

    static func clear() {
        cached = nil
        try? KeychainStore.remove(key)
    }
}
