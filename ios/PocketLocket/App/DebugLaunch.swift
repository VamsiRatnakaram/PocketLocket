import Foundation
import SwiftData

/// Debug-only launch hooks used by `scripts/appstore-screenshots.sh`.
///
/// Compiled out of Release entirely (`#if DEBUG` at the call site and here), so
/// no argument parsing or seeding code ever ships. This mirrors the existing
/// `-tab` launch argument in `MainTabView.initialTab()`.
enum DebugLaunch {
    /// `xcrun simctl launch <udid> <bundle-id> -seedSimpleFIN <access-url>`
    ///
    /// Stores a SimpleFIN *access URL* (the long-lived credential produced by
    /// claiming a setup token) directly, so a screenshot run can populate real
    /// demo data without the one-time token claim — demo tokens are single-use
    /// and can't be re-claimed once consumed.
    ///
    /// Accepts only SimpleFIN's public demo host; anything else is ignored so a
    /// mistyped argument can never write a real bank credential into a build
    /// that might be screenshotted and published.
    static func seedSimpleFINIfNeeded() {
        let args = CommandLine.arguments
        // Optional `-budget <value>` so a screenshot run shows an on-track
        // state instead of the default $3,000 budget (which the demo's ~$5,181
        // spend would blow past into a red "over budget" screen).
        if let bi = args.firstIndex(of: "-budget"), bi + 1 < args.count,
           let value = Double(args[bi + 1]), value > 0 {
            UserDefaults.standard.set(value, forKey: "monthlyBudget")
        }
        guard let index = args.firstIndex(of: "-seedSimpleFIN"), index + 1 < args.count else { return }
        let url = args[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let comps = URLComponents(string: url),
            comps.scheme == "https",
            comps.host == "beta-bridge.simplefin.org",
            comps.user == "demo",
            comps.password == "demo"
        else {
            NSLog("PocketLocket DebugLaunch: refused to seed non-demo SimpleFIN URL")
            return
        }
        // Never clobber a real connection the user set up themselves.
        guard !SimpleFINStore.isConnected else {
            NSLog("PocketLocket DebugLaunch: SimpleFIN already connected; leaving it alone")
            return
        }
        SimpleFINStore.seedForScreenshots(url)
        NSLog("PocketLocket DebugLaunch: seeded demo SimpleFIN access URL")
    }

    /// Debug-only, post-sync polish for screenshot runs: the public demo feed
    /// contains a placeholder account literally named "SimpleFIN Empty
    /// Account", which would read as a bug in a store listing. Renaming via
    /// `officialName` survives later syncs (`SyncService` only refreshes
    /// `name`), so this is applied once after each refresh and persists.
    static func applyScreenshotFixups(context: ModelContext) {
        guard CommandLine.arguments.contains("-seedSimpleFIN") else { return }
        let descriptor = FetchDescriptor<AccountRecord>(
            predicate: #Predicate { $0.name == "SimpleFIN Empty Account" }
        )
        guard let matches = try? context.fetch(descriptor), !matches.isEmpty else { return }
        for account in matches {
            account.officialName = "SimpleFIN Backup Checking"
        }
        try? context.save()
        NSLog("PocketLocket DebugLaunch: renamed placeholder demo account")
    }
}
