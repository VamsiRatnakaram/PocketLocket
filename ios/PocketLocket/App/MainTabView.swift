import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var selection: Tab = MainTabView.initialTab()
    @Environment(\.modelContext) private var context

    enum Tab: Hashable { case home, transactions, accounts, analysis }

    var body: some View {
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
        .task {
            try? await SyncService.shared.refresh(context: context)
        }
    }

    /// Allows `-tab <home|transactions|accounts|analysis>` at launch (used for testing).
    static func initialTab() -> Tab {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "-tab"), index + 1 < args.count {
            switch args[index + 1] {
            case "transactions": return .transactions
            case "accounts": return .accounts
            case "save", "analysis": return .analysis
            default: return .home
            }
        }
        return .home
    }
}
