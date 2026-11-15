import Foundation

/// The only URLs a widget is allowed to hand the app.
///
/// Tapping a widget cannot skip the lock: the app still shows `LockView` until
/// Face ID passes, so every link here means "open the app and land on this tab",
/// never "show this data". Keeping the construction in one place means the
/// widget and `.onOpenURL` can't disagree about the format.
enum WidgetDeepLink {
    static let scheme = "pocketlocket"
    static let host = "widget"

    /// Which tab to show once the app has unlocked.
    enum Destination: String, Equatable {
        case home
        case transactions
    }

    /// Opens the app on Home.
    static func home() -> URL {
        URL(string: "\(scheme)://\(host)/home") ?? URL(string: "\(scheme)://\(host)")!
    }

    /// Opens the app on Home with one category's drill-down already showing.
    static func category(_ category: SpendCategory) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/category"
        components.queryItems = [URLQueryItem(name: "id", value: category.rawValue)]
        return components.url
    }

    /// `nil` for anything that isn't ours, so unrelated links are ignored.
    static func destination(from url: URL) -> Destination? {
        guard url.scheme == scheme, url.host == host else { return nil }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return Destination(rawValue: path)
    }

    /// A category to open after unlocking, when the link asked for one.
    static func category(from url: URL) -> SpendCategory? {
        guard url.scheme == scheme, url.host == host,
              url.path.hasPrefix("/category"),
              let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?
                  .first(where: { $0.name == "id" })?
                  .value
        else { return nil }
        return SpendCategory(rawValue: raw)
    }
}
