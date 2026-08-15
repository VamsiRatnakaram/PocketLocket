import Foundation
import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @AppStorage("monthlyBudget") private var monthlyBudget: Double = 3000
    @AppStorage("ringStyle") private var ringStyleRaw: String = RingStyle.donut.rawValue
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.system.rawValue
    @State private var simplefinConnected = false
    @State private var earliestSyncedDate: Date?
    @State private var showSimpleFIN = false
    @State private var showBackup = false
    @State private var showDisconnectConfirmation = false
    @State private var disconnectErrorMessage: String?
    @State private var showResetConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Monthly budget") {
                    HStack {
                        Text("Budget")
                        Spacer()
                        TextField("Budget", value: $monthlyBudget, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                    NavigationLink {
                        CategoryBudgetsView()
                    } label: {
                        Label("Category budgets", systemImage: "chart.bar.fill")
                    }
                }

                Section("Spend ring style") {
                    Picker("Style", selection: $ringStyleRaw) {
                        ForEach(RingStyle.allCases) { style in
                            Text(style.label).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearanceModeRaw) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button { showSimpleFIN = true } label: {
                        HStack {
                            Label("SimpleFIN", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            Text(simplefinConnected ? "Connected" : "Not connected")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    if simplefinConnected {
                        Button(role: .destructive) {
                            showDisconnectConfirmation = true
                        } label: {
                            Text("Disconnect SimpleFIN")
                        }
                    }
                } header: {
                    Text("Connections")
                } footer: {
                    if simplefinConnected, let earliestDataText {
                        Text(earliestDataText)
                    }
                }

                Section {
                    NavigationLink {
                        RulesView()
                    } label: {
                        Label("Category rules", systemImage: "wand.and.stars")
                    }
                } header: {
                    Text("Categorization")
                } footer: {
                    Text("Edit categories and their rules here. Merchant grouping can be corrected from any transaction or from a merchant in Analysis.")
                }

                Section("Help & Privacy") {
                    if let supportURL {
                        Link(destination: supportURL) {
                            Label("Contact Support", systemImage: "envelope")
                        }
                    }
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }

                Section {
                    Button { showBackup = true } label: {
                        Label("Backup & Transfer…", systemImage: "lock.doc")
                    }
                    Button(role: .destructive) { showResetConfirmation = true } label: {
                        Text("Reset local data")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Export a password-protected backup to move data to another device, or reset everything on this one.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showSimpleFIN) {
                SimpleFINConnectView { simplefinConnected = true }
            }
            .sheet(isPresented: $showBackup) { BackupView() }
            .onAppear { simplefinConnected = SimpleFINStore.isConnected }
            .task { earliestSyncedDate = loadEarliestSyncedDate() }
            .confirmationDialog(
                "Disconnect SimpleFIN?",
                isPresented: $showDisconnectConfirmation,
                titleVisibility: .visible
            ) {
                Button("Disconnect and Keep Data") { disconnectSimpleFIN(deleteSyncedData: false) }
                Button("Disconnect and Delete Data", role: .destructive) {
                    disconnectSimpleFIN(deleteSyncedData: true)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose whether transactions and accounts synced from SimpleFIN stay on this device. Imported and manual data will not be deleted.")
            }
            .confirmationDialog(
                "Reset local data?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset and Keep Connection", role: .destructive) {
                    resetLocalData(disconnectSimpleFIN: false)
                }
                Button("Reset and Disconnect SimpleFIN", role: .destructive) {
                    resetLocalData(disconnectSimpleFIN: true)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes every account, transaction, category rule, merchant-grouping correction, and reimbursement allocation on this device. Keeping the connection lets the next sync pull your SimpleFIN data back; disconnecting means re-entering your setup token.")
            }
            .alert(
                "Couldn’t Delete SimpleFIN Data",                isPresented: Binding(
                    get: { disconnectErrorMessage != nil },
                    set: { if !$0 { disconnectErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { disconnectErrorMessage = nil }
            } message: {
                Text(disconnectErrorMessage ?? "Please try again.")
            }
        }
        .presentationDragIndicator(.visible)
        .platformPresentationCornerRadius(30)
    }

    /// Shows the oldest synced transaction date so you can tell whether
    /// SimpleFIN/your bank is providing more history than what's currently
    /// visible — the app always requests 24 months, but each bank's own
    /// feed decides how far back it actually returns.
    /// One row, fetched once when Settings opens.
    ///
    /// A `@Query` here loaded and retained every transaction on file — sorted,
    /// unfiltered, and refreshed on every change — just to read a single date,
    /// and did it even when SimpleFIN was never connected.
    private func loadEarliestSyncedDate() -> Date? {
        var descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate { $0.accountId?.starts(with: "sf-") ?? false },
            sortBy: [SortDescriptor(\TransactionRecord.date, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first?.date
    }

    private var earliestDataText: String? {
        // Only consider SimpleFIN-synced transactions (accountId prefixed "sf-"),
        // not manually-entered or CSV-imported records, so this reflects what the
        // bank's own feed actually returned rather than any back-dated manual entry.
        guard let earliest = earliestSyncedDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let months = max(0, Calendar.current.dateComponents([.month], from: earliest, to: Date()).month ?? 0)
        return "Oldest synced transaction: \(formatter.string(from: earliest)) (~\(months) month\(months == 1 ? "" : "s") of history). PocketLocket requests up to 24 months, but each bank's SimpleFIN feed decides how far back it actually shares."
    }

    private var supportURL: URL? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return SupportEmail.url(
            version: version,
            build: build,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    /// Deletes everything this device holds. The SimpleFIN connection is kept
    /// or dropped on request: a reset is usually about clearing bad data, and
    /// re-entering a setup token to get the same accounts back is busywork —
    /// but someone handing the phone on wants the credential gone too.
    private func resetLocalData(disconnectSimpleFIN: Bool) {
        try? context.delete(model: ReimbursementAllocation.self)
        try? context.delete(model: TransactionRecord.self)
        try? context.delete(model: AccountRecord.self)
        try? context.delete(model: CategoryRule.self)
        try? context.delete(model: MerchantGroupingRule.self)
        try? context.save()
        if disconnectSimpleFIN {
            SimpleFINStore.clear()
            simplefinConnected = false
        }
        dismiss()
    }

    private func disconnectSimpleFIN(deleteSyncedData: Bool) {
        if deleteSyncedData {
            do {
                try SimpleFINDataStore.deleteSyncedData(in: context)
            } catch {
                disconnectErrorMessage = error.localizedDescription
                return
            }
        }
        SimpleFINStore.clear()
        simplefinConnected = false
    }
}
