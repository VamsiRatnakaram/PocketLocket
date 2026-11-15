import Foundation

/// The App Group shared between the app and the widget extension.
///
/// A widget runs in its own process: it cannot open the app's SwiftData store
/// and it cannot read the Face ID–bound SimpleFIN token. So the app *pushes* a
/// small, already-computed snapshot into this suite and the widget only ever
/// reads that. The widget never fetches, never opens the ledger, and never
/// touches the Keychain — which is what keeps the on-device promise intact.
///
/// Both targets must resolve the same identifier. It comes from `APP_GROUP_ID`
/// in the xcconfigs, surfaced to Swift through the target's Info.plist so a
/// changed bundle prefix can't silently split the app from its widget. The
/// fallback covers Xcode Previews, which run in the app's process where that
/// plist key may be absent.
enum AppGroup {
    /// Info.plist key written from the `APP_GROUP_ID` build setting.
    static let infoPlistKey = "AppGroupIdentifier"

    static let fallbackIdentifier = "group.com.vratnakaram.PocketLocket"

    static let identifier: String = {
        if let fromPlist = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String,
           !fromPlist.isEmpty {
            return fromPlist
        }
        return fallbackIdentifier
    }()

    /// The shared defaults suite. Falls back to the standard suite in
    /// development setups where the App Group entitlement is unavailable (a
    /// free personal Apple ID cannot register app groups), so previews and
    /// simulator runs still show real data.
    static let defaults = UserDefaults(suiteName: identifier) ?? .standard
}
