import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Password-protected export/import so data can be moved securely between
/// devices. The file is AES-GCM encrypted — useless without the password.
struct BackupView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var exportPassword = ""
    @State private var exportConfirm = ""
    @State private var exportDoc: EncryptedBackupDocument?
    @State private var showExporter = false

    @State private var showImporter = false
    @State private var pendingImport: Data?
    @State private var importPassword = ""
    @State private var askImportPassword = false

    @State private var message: String?
    @State private var isError = false

    private var passwordsValid: Bool {
        !exportPassword.isEmpty && exportPassword == exportConfirm
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Password", text: $exportPassword)
                        .textContentType(.newPassword)
                    SecureField("Confirm password", text: $exportConfirm)
                        .textContentType(.newPassword)
                    Button {
                        startExport()
                    } label: {
                        Label("Export encrypted backup…", systemImage: "lock.doc")
                    }
                    .disabled(!passwordsValid)
                } header: {
                    Text("Export")
                } footer: {
                    Text("Saves an encrypted file with all your accounts, transactions, category rules, merchant-grouping corrections, and reimbursement allocations. You'll need this password to restore it — it cannot be recovered.")
                }

                Section {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import from backup…", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Import")
                } footer: {
                    Text("Restore from a backup made on another device. Existing items are kept; only new ones are added.")
                }
            }
            .navigationTitle("Backup & Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDoc,
                contentType: .json,
                defaultFilename: "BudgetBackup-\(Self.dateStamp)"
            ) { result in
                switch result {
                case .success: show("Backup saved. Keep the file and password safe.", isError: false)
                case .failure(let error): show(error.localizedDescription, isError: true)
                }
                exportPassword = ""
                exportConfirm = ""
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .data]) { result in
                switch result {
                case .success(let url): loadImport(url)
                case .failure(let error): show(error.localizedDescription, isError: true)
                }
            }
            .alert("Backup password", isPresented: $askImportPassword) {
                SecureField("Password", text: $importPassword)
                Button("Import") { performImport() }
                Button("Cancel", role: .cancel) { pendingImport = nil; importPassword = "" }
            } message: {
                Text("Enter the password used to create this backup.")
            }
            .alert(isError ? "Error" : "Done", isPresented: messageBinding) {
                Button("OK", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
        .presentationDragIndicator(.visible)
        .platformPresentationCornerRadius(30)
    }

    private var messageBinding: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }

    private static var dateStamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func startExport() {
        guard passwordsValid else { return }
        do {
            let data = try BackupService.exportEncrypted(password: exportPassword, context: context)
            exportDoc = EncryptedBackupDocument(data: data)
            showExporter = true
        } catch {
            show(error.localizedDescription, isError: true)
        }
    }

    private func loadImport(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            show("Could not read that file.", isError: true)
            return
        }
        pendingImport = data
        importPassword = ""
        askImportPassword = true
    }

    private func performImport() {
        guard let data = pendingImport else { return }
        do {
            let count = try BackupService.importEncrypted(data, password: importPassword, context: context)
            show("Imported \(count) new transaction\(count == 1 ? "" : "s").", isError: false)
        } catch {
            show(error.localizedDescription, isError: true)
        }
        pendingImport = nil
        importPassword = ""
    }

    private func show(_ text: String, isError: Bool) {
        self.isError = isError
        self.message = text
    }
}

/// Wraps the already-encrypted bytes for `fileExporter`.
struct EncryptedBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .data] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
