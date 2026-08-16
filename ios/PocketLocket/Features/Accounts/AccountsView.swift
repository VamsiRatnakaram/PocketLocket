import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AccountsView: View {
    @Query(sort: \AccountRecord.name) private var accounts: [AccountRecord]
    @Environment(\.modelContext) private var context
    @AppStorage(SpendingAccountFilter.key) private var excludedAccountsRaw = ""
    @State private var showSimpleFIN = false
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var errorMessage: String?
    @State private var isSyncing = false

    private func isIncluded(_ account: AccountRecord) -> Bool {
        !SpendingAccountFilter.excludedIds(from: excludedAccountsRaw).contains(account.id)
    }
    private var balanceSummary: AccountBalanceSummary.Totals {
        AccountBalanceSummary.totals(for: accounts.map {
            AccountBalanceSummary.Account(
                type: $0.resolvedType,
                balance: $0.currentBalance
            )
        })
    }
    private var assets: Double { balanceSummary.assets }
    private var liabilities: Double { balanceSummary.liabilities }
    private var netWorth: Double { balanceSummary.netWorth }
    private var investmentAccounts: [AccountRecord] {
        accounts.filter { $0.resolvedType == "investment" }
    }
    private var bankingAccounts: [AccountRecord] {
        accounts.filter { $0.resolvedType != "investment" }
    }

    private var importAlertBinding: Binding<Bool> {
        Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func refresh() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await SyncService.shared.refresh(context: context)
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let count = try ImportService.importFile(at: url, into: context)
                importMessage = "Imported \(count) transaction\(count == 1 ? "" : "s")."
            } catch {
                importMessage = "Couldn't import: \(error.localizedDescription)"
            }
        case .failure(let error):
            importMessage = error.localizedDescription
        }
    }

    private func summaryColumn(_ title: String, _ value: Double, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(CurrencyFormatter.string(value))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !accounts.isEmpty {
                    Section {
                        VStack(spacing: 10) {
                            Text("Net worth")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(CurrencyFormatter.string(netWorth))
                                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            HStack {
                                summaryColumn("Assets", assets, .green)
                                Spacer()
                                summaryColumn("Liabilities", liabilities, .red)
                            }
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }

                if !bankingAccounts.isEmpty {
                    Section {
                        ForEach(bankingAccounts) { account in
                            accountRow(account)
                        }
                    } header: {
                        Text("Banking & Credit")
                    } footer: {
                        Text("Use the circle to include or exclude an account from spending. Tap the account for details.")
                    }
                }

                if !investmentAccounts.isEmpty {
                    Section {
                        ForEach(investmentAccounts) { account in
                            accountRow(account)
                        }
                    } header: {
                        Text("Investments")
                    } footer: {
                        Text("Investment accounts are excluded from spending by default. Use the circle to include one; tap the account for details.")
                    }
                }
            }
            .navigationTitle("Accounts")
            .refreshable { await refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isSyncing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showSimpleFIN = true } label: { Label("Auto-sync (SimpleFIN)", systemImage: "arrow.triangle.2.circlepath") }
                        Button { showImporter = true } label: { Label("Import statement (free)", systemImage: "square.and.arrow.down") }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showSimpleFIN) { SimpleFINConnectView() }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: ImportService.allowedTypes) { result in
                handleImport(result)
            }
            .alert("Import", isPresented: importAlertBinding) {
                Button("OK", role: .cancel) { importMessage = nil }
            } message: { Text(importMessage ?? "") }
            .alert("Something went wrong", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .overlay {
                if accounts.isEmpty {
                    ContentUnavailableView {
                        Label("No accounts", systemImage: "building.columns")
                    } description: {
                        Text("Auto-sync with SimpleFIN or import a statement to get started.")
                    } actions: {
                        Button("Connect an account") { showSimpleFIN = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private func accountRow(_ account: AccountRecord) -> some View {
        HStack(spacing: 4) {
            Button {
                excludedAccountsRaw = SpendingAccountFilter.toggling(
                    account.id,
                    in: excludedAccountsRaw
                )
            } label: {
                Image(systemName: isIncluded(account) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isIncluded(account) ? Color.accentColor : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isIncluded(account)
                    ? "Exclude \(account.displayName) from spending"
                    : "Include \(account.displayName) in spending"
            )

            NavigationLink {
                AccountDetailView(account: account)
            } label: {
                AccountCard(account: account)
                    .opacity(isIncluded(account) ? 1 : 0.45)
            }
            .foregroundStyle(.primary)
        }
    }
}
