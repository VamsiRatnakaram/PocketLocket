import Foundation
import Observation

/// Carries a widget tap through to wherever it should land.
///
/// A widget can launch the app but cannot see inside it, and the app is locked
/// until Face ID passes — so a link can never mean "navigate now", only "go
/// here once you're in". Holding the request here rather than acting on it in
/// `.onOpenURL` is what keeps a widget tap from either dead-ending on `LockView`
/// or navigating a view that hasn't been created yet.
@Observable
final class AppRouter {
    var pendingTab: WidgetDeepLink.Destination?
    var pendingCategory: SpendCategory?

    /// Consumes a queued tab. Called by `MainTabView` once it exists.
    func takeTab() -> WidgetDeepLink.Destination? {
        defer { pendingTab = nil }
        return pendingTab
    }

    /// Consumes a queued category. Called by `HomeView` once it exists.
    func takeCategory() -> SpendCategory? {
        defer { pendingCategory = nil }
        return pendingCategory
    }

    func handle(url: URL) {
        pendingTab = WidgetDeepLink.destination(from: url) ?? .home
        pendingCategory = WidgetDeepLink.category(from: url)
    }
}
