import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var isImporting = false
    @State private var alertMessage: String? = nil
    @State private var showingAlert = false
    @State private var showingRestoreConfirm = false
    @State private var pendingRestoreURL: URL? = nil
    @State private var exportURL: URL? = nil
    @State private var showingShareSheet = false

    var body: some View {
        Form {
            Section("Backup & Restore") {
                Button("Export Backup") {
                    Task { await exportBackup() }
                }

                Button("Import Backup") {
                    isImporting = true
                }
                .foregroundStyle(.orange)
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                pendingRestoreURL = url
                showingRestoreConfirm = true
            }
        }
        .confirmationDialog(
            "Restore Backup",
            isPresented: $showingRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                if let url = pendingRestoreURL {
                    Task { await restoreBackup(from: url) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace all current data. Restart the app after restore to see changes.")
        }
        .alert(alertMessage ?? "", isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    private func exportBackup() async {
        do {
            exportURL = try await BackupRepository.shared.backup()
            showingShareSheet = true
        } catch {
            alertMessage = "Export failed: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func restoreBackup(from url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            try await BackupRepository.shared.stageRestore(from: url)
            alertMessage = "Restore staged. Please restart the app to apply changes."
            showingAlert = true
        } catch {
            alertMessage = "Restore failed: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
