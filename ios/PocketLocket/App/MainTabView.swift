import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var selection: Tab = MainTabView.initialTab()
    @Environment(\.modelContext) private var context

    enum Tab: Hashable { case home, transactions, accounts, analysis }

    var body: some View {
        tabs
            .liquidGlassTabBarMinimizeOnScroll()
            .task {
                // Backfill first so existing history (and CSV imports, which
                // never touch the sync path) gets paired even when there's no
                // SimpleFIN connection or the refresh below fails.
                do {
                    try TransferMatchService.recompute(
                        in: context,
                        saveChanges: false
                    )
                    try ReimbursementAllocationService.reconcile(in: context)
                    try context.save()
                } catch {
                    context.rollback()
                }
                try? await SyncService.shared.refresh(context: context)
            }
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selection) {
                SwiftUI.Tab("Home", systemImage: "chart.pie.fill", value: Tab.home) {
                    HomeView()
                }
                SwiftUI.Tab("Transactions", systemImage: "list.bullet", value: Tab.transactions) {
                    TransactionsView()
                }
                SwiftUI.Tab("Accounts", systemImage: "building.columns.fill", value: Tab.accounts) {
                    AccountsView()
                }
                SwiftUI.Tab(
                    "Analysis",
                    systemImage: "chart.line.uptrend.xyaxis",
                    value: Tab.analysis
                ) {
                    AnalysisRootView()
                }
            }
        } else {
            legacyTabs
        }
    }

    private var legacyTabs: some View {
        TabView(selection: $selection) {
            HomeView()
                .tag(Tab.home)
                .tabItem { Label("Home", systemImage: "chart.pie.fill") }

            TransactionsView()
                .tag(Tab.transactions)
                .tabItem { Label("Transactions", systemImage: "list.bullet") }

            AccountsView()
                .tag(Tab.accounts)
                .tabItem { Label("Accounts", systemImage: "building.columns.fill") }

            AnalysisRootView()
                .tag(Tab.analysis)
                .tabItem { Label("Analysis", systemImage: "chart.line.uptrend.xyaxis") }
        }
    }

    /// Allows `-tab <home|transactions|accounts|insights>` at launch (used for testing).
    static func initialTab() -> Tab {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "-tab"), index + 1 < args.count {
            switch args[index + 1] {
            case "transactions": return .transactions
            case "accounts": return .accounts
            case "save", "analysis", "insights": return .analysis
            default: return .home
            }
        }
        return .home
    }
}
