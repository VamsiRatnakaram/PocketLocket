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
    @State private var showSimpleFIN = false
    @State private var showBackup = false
    @State private var showDisconnectConfirmation = false
    @State private var disconnectErrorMessage: String?

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

                Section("Connections") {
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
                }

                Section {
                    NavigationLink {
                        RulesView()
                    } label: {
                        Label("Category rules", systemImage: "wand.and.stars")
                    }
                } header: {
                    Text("Categorization")
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
                    Button(role: .destructive) { resetLocalData() } label: {
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
            .alert(
                "Couldn’t Delete SimpleFIN Data",
                isPresented: Binding(
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

    private var supportURL: URL? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return SupportEmail.url(
            version: version,
            build: build,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    private func resetLocalData() {
        try? context.delete(model: TransactionRecord.self)
        try? context.delete(model: AccountRecord.self)
        try? context.delete(model: CategoryRule.self)
        try? context.save()
        SimpleFINStore.clear()
        simplefinConnected = false
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
