import SwiftUI
import SwiftData

/// Connects a SimpleFIN Bridge account (read-only, ~$15/yr, no backend). The
/// user pastes a one-time setup token; we claim an access URL, store it in the
/// Keychain, and sync — all on-device.
struct SimpleFINConnectView: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var onConnected: () -> Void = {}

    @State private var token = ""
    @State private var phase: Phase = .input

    private enum Phase: Equatable {
        case input
        case working
        case error(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("SimpleFIN gives this app **read-only** access to your accounts for about $15/year. Your bank login is entered on SimpleFIN — never shared with this app — and no data is stored on any server we run.")
                    Link(destination: URL(string: "https://bridge.simplefin.org/simplefin/create")!) {
                        Label("1. Get a setup token at SimpleFIN Bridge", systemImage: "safari")
                    }
                }

                Section("2. Paste your setup token") {
                    TextEditor(text: $token)
                        .frame(minHeight: 90)
                        .font(.footnote.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if case let .error(message) = phase {
                    Section {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section {
                    Button(action: { Task { await connect() } }) {
                        HStack {
                            if phase == .working { ProgressView() }
                            Text(phase == .working ? "Connecting…" : "Connect")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || phase == .working)
                }
            }
            .navigationTitle("SimpleFIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }

    private func connect() async {
        phase = .working
        do {
            let accessURL = try await SimpleFINClient().claim(setupToken: token)
            SimpleFINStore.save(accessURL)
            try await SyncService.shared.refresh(context: context)
            onConnected()
            dismiss()
        } catch {
            phase = .error(error.localizedDescription)
        }
    }
}
