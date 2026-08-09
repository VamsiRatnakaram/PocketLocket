import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section {
                Text("Effective July 20, 2026")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Budget is a local-first personal budgeting app. This policy explains how the app handles your information.")
            } header: {
                Text("Overview")
            }

            Section("Information stored on your device") {
                Text("Budget stores account names, balances, transactions, categories, rules, preferences, and optional budgets in its local SwiftData store on your device.")
                Text("If you connect SimpleFIN, the app stores its read-only access URL in the device Keychain, protected by Face ID, Touch ID, or your passcode when available.")
            }

            Section("Optional SimpleFIN connection") {
                Text("SimpleFIN is optional. When you choose to connect it, the app communicates directly with SimpleFIN over HTTPS to retrieve the accounts and transactions you authorize. Budget does not operate a backend or receive a copy of that data.")
                Link("SimpleFIN privacy information", destination: URL(string: "https://www.simplefin.org/")!)
            }

            Section("Privacy protections") {
                Text("Budget does not include advertising, analytics, or tracking SDKs. It does not sell your information or create an app account for you.")
                Text("Face ID and Touch ID are handled by Apple. Budget receives only the authentication result, never biometric data.")
                Text("On supported devices, you can ask Apple Intelligence questions about recent transactions. Questions and transaction context are processed on-device and are not sent to a server operated by the developer.")
            }

            Section("Backups and control") {
                Text("Encrypted backups are created only when you request them. The app saves them to the location you choose, and the backup password is not retained by the app.")
                Text("Use Settings > Reset local data to remove Budget's local accounts, transactions, rules, and SimpleFIN connection from this device. You can also revoke SimpleFIN access through SimpleFIN.")
            }

            Section("Contact and changes") {
                Text("This policy may change when the app changes. For privacy questions, contact the developer by email.")
                if let supportURL = URL(string: "mailto:vamsiratnakaram@gmail.com?subject=Budget%20Privacy%20Question") {
                    Link("Email privacy support", destination: supportURL)
                }
            }
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}