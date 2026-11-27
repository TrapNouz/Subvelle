import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CoreTransferable
import SubspaceCore

/// Data export avoids FileDocument's iOS 27 deprecation and also works on iOS 26.
struct BackupExport: Transferable, Sendable {
    var data: Data = Data()
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { item in item.data }
    }
}
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    /// One file picker for the whole screen: SwiftUI mishandles several `fileImporter`s in one
    /// hierarchy (the inner one took over, so Import showed a folders-only picker).
    @State private var picking = false
    @State private var pickMode = FilePickMode.backupFile
    @State private var exporting = false
    @State private var document = BackupExport()
    @State private var pendingImport: Data?
    @State private var importCount = 0
    @State private var confirmation = false
    @State private var result: String?
    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("General") {
                    LabeledContent("Active subscriptions", value: String(store.summary.activeCount))
                    NavigationLink("About Subvelle") { AboutSubspaceView() }
                }
                Section {
                    CurrencyPicker(selection: $store.currency, title: "Reporting currency")
                    if store.rates.updatedAt == .distantPast { Text("No cached rates yet").foregroundStyle(.secondary) }
                    else { LabeledContent("Rates updated", value: store.rates.updatedAt.formatted(date: .abbreviated, time: .omitted)) }
                    if store.rates.isStale { Label("Rates may be out of date", systemImage: "clock.badge.exclamationmark").font(.caption).foregroundStyle(.orange) }
                    Button { Task { await store.refreshRates() } } label: {
                        HStack { Text("Refresh rates"); Spacer(); if store.refreshingRates { ProgressView() } else { Image(systemName: "arrow.clockwise") } }
                    }.disabled(store.refreshingRates)
                } header: { Text("Currency & exchange rates") } footer: { Text("Cached for offline use. Missing currency pairs are excluded from totals and flagged.") }
                Section("Appearance") {
                    Picker("Theme", selection: $store.appearance) { Text("Dark").tag("dark"); Text("Follow system").tag("system") }
                    Text("Glass appearance follows your iPhone’s accessibility and appearance settings.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Renewal reminders", isOn: Binding(get: { store.remindersEnabled }, set: { enabled in
                        if enabled { Task { await store.enableReminders() } }
                        else { store.remindersEnabled = false; store.scheduleNotifications() }
                    })).accessibilityIdentifier("renewalReminders")
                    Picker("Default notice", selection: $store.defaultReminder) { ForEach([1,3,7,14], id: \.self) { Text("\($0) days before").tag($0) } }
                    if let message = store.notificationMessage {
                        DisclosureGroup("Reminder status") { Text(message).font(.caption).foregroundStyle(.secondary) }
                    }
                    Button("iOS notification settings", systemImage: "arrow.up.forward.app") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                } header: { Text("Notifications") } footer: { Text("Delivered at 9 AM local time. Open Subvelle periodically to refresh the queue. Defaults apply to new plans.") }
                Section {
                    Button("Export backup", systemImage: "square.and.arrow.up") {
                        do { document = BackupExport(data: try store.backupData()); exporting = true }
                        catch { store.error = error.localizedDescription }
                    }.accessibilityIdentifier("exportBackup")
                    Button("Import backup", systemImage: "square.and.arrow.down") { pickMode = .backupFile; picking = true }.accessibilityIdentifier("importBackup")
                    if let result { Text(result).font(.caption).foregroundStyle(.secondary) }
                } header: { Text("Backup & restore") } footer: { Text("JSON backups include all plans. Import replaces matching IDs and preserves other plans. Export a recovery copy first.") }
                AutoBackupSection(chooseFolder: { pickMode = .folder; picking = true })
                UpdatesSection()
                Section("Privacy & information") {
                    Label("On-device storage", systemImage: "internaldrive")
                    Label("No accounts, ads, or tracking", systemImage: "hand.raised")
                    NavigationLink("Data & privacy details") { PrivacyDetailsView() }
                    Text("Built for a clearer financial orbit.").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("settingsBottom")
                }
            }.navigationTitle("Settings")
                .accessibilityIdentifier("settingsScroll")
                .scrollEdgeEffectStyle(.hard, for: .bottom)
                .subscriptionToolbar()
                .fileExporter(isPresented: $exporting, item: document, contentTypes: [.json], defaultFilename: "Subvelle-\(Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash)))", onCompletion: { outcome in
                    // ISO 8601 formatting defaults to UTC; use the local day so evening exports are not dated tomorrow.
                    switch outcome { case .success: result = "Backup exported."; store.markExported(); case .failure(let error): store.error = error.localizedDescription }
                })
                // Apple's document picker directly, instead of SwiftUI's fileImporter, which on iOS 26
                // could open the picker without accepting the tapped file.
                .sheet(isPresented: $picking) {
                    DocumentPicker(types: pickMode.contentTypes, copiesFile: pickMode == .backupFile) { url in
                        picking = false
                        handlePicked(url)
                    } onCancel: { picking = false }
                    .ignoresSafeArea()
                }
                .alert("Import \(importCount) subscriptions?", isPresented: $confirmation) {
                    Button("Merge backup") {
                        guard let pendingImport else { return }
                        do { let count = try store.importBackup(pendingImport); result = "Imported \(count) subscriptions."; self.pendingImport = nil }
                        catch { store.error = error.localizedDescription }
                    }
                    Button("Cancel", role: .cancel) { pendingImport = nil }
                } message: { Text("Matching subscriptions will be replaced and others kept. Export a backup first if needed.") }
        }
    }
}

extension SettingsView {
    fileprivate func handlePicked(_ url: URL) {
        switch pickMode {
        case .folder:
            Task { await store.setBackupFolder(url) }
        case .backupFile:
            Task {
                do {
                    // Off the main actor; the picker already copied the file into the app.
                    let (data, count) = try await Task.detached(priority: .userInitiated) { try AppStore.readBackupFile(at: url) }.value
                    pendingImport = data; importCount = count
                    // Ask only after the picker has finished closing.
                    try? await Task.sleep(for: .milliseconds(600))
                    confirmation = true
                } catch { store.error = error.localizedDescription }
            }
        }
    }
}

/// UIKit's document picker. With `copiesFile`, the chosen file is copied into the app (downloading it
/// from iCloud first) and the copy's URL is returned; otherwise the original, security-scoped URL.
struct DocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    let copiesFile: Bool
    let onPick: (URL) -> Void
    let onCancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: copiesFile)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {
        context.coordinator.onPick = onPick
        context.coordinator.onCancel = onCancel
    }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL) -> Void
        var onCancel: () -> Void
        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) { self.onPick = onPick; self.onCancel = onCancel }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) } else { onCancel() }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onCancel() }
    }
}

/// Settings › About & updates: the installed version, the project on GitHub, and a manual check
/// for a newer release.
struct UpdatesSection: View {
    private enum Result: Equatable { case upToDate(String), available(ReleaseInfo), failed(String) }
    @State private var checking = false
    @State private var result: Result?
    var body: some View {
        Section {
            LabeledContent("Installed version", value: UpdateService.installedVersion).accessibilityIdentifier("installedVersion")
            Link(destination: UpdateService.repository) {
                Label("Subvelle on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }.accessibilityIdentifier("githubLink")
            Button { Task { await check() } } label: {
                HStack {
                    Label("Check for updates", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if checking { ProgressView() }
                }
            }
            .disabled(checking).accessibilityIdentifier("checkForUpdates")
            switch result {
            case .upToDate(let version):
                Label("You’re up to date (\(version))", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.subheadline)
            case .available(let release):
                Label("Subvelle \(release.version) is available", systemImage: "sparkles").foregroundStyle(Color.spaceAccent).font(.subheadline.weight(.semibold))
                Link(destination: release.url) { Label("Download from GitHub", systemImage: "arrow.down.circle.fill") }
                    .accessibilityIdentifier("downloadUpdate")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
            case nil:
                EmptyView()
            }
        } header: { Text("About & updates") } footer: {
            Text("Checks GitHub’s public list of releases only when you tap. Nothing about you or your subscriptions is sent. Install a new version the same way as before, with SideStore.")
        }
    }
    private func check() async {
        checking = true
        defer { checking = false }
        do {
            let latest = try await UpdateService.latest()
            let installed = UpdateService.installedVersion
            result = AppVersion.isNewer(latest.version, than: installed) ? .available(latest) : .upToDate(installed)
        } catch {
            result = .failed("Couldn’t check for updates. \(error.localizedDescription)")
        }
    }
}

enum FilePickMode {
    case backupFile, folder
    /// Backups are matched broadly: files shared from other apps are often typed as plain text or
    /// generic data rather than JSON. The contents are validated before anything is imported.
    var contentTypes: [UTType] { self == .folder ? [.folder] : [.json, .plainText, .data] }
}

/// Automatic backups into a folder the user picks, typically in iCloud Drive. The folder picker is
/// the Settings screen's single file picker (see `FilePickMode`).
struct AutoBackupSection: View {
    @Environment(AppStore.self) private var store
    var chooseFolder: () -> Void
    @State private var confirmingStop = false
    var body: some View {
        Section {
            if let folder = store.backupFolderName {
                LabeledContent("Folder") { Label(folder, systemImage: "folder").labelStyle(.titleAndIcon) }
                LabeledContent("Last backup", value: store.lastBackup.map { $0.formatted(.relative(presentation: .named)) } ?? "Not yet")
                    .accessibilityIdentifier("lastBackup")
                if let problem = store.backupProblem {
                    Label(problem, systemImage: "exclamationmark.icloud").font(.caption).foregroundStyle(.orange)
                }
                Button { Task { await store.backUpNow() } } label: {
                    HStack { Text("Back up now"); Spacer(); if store.backingUp { ProgressView() } else { Image(systemName: "arrow.clockwise.icloud") } }
                }.disabled(store.backingUp)
                Button("Change folder", systemImage: "folder.badge.gearshape") { chooseFolder() }
                Button("Turn off automatic backup", systemImage: "icloud.slash", role: .destructive) { confirmingStop = true }
            } else {
                Button("Choose backup folder", systemImage: "icloud.and.arrow.up") { chooseFolder() }
                    .accessibilityIdentifier("chooseBackupFolder")
                if let problem = store.backupProblem {
                    Label(problem, systemImage: "exclamationmark.icloud").font(.caption).foregroundStyle(.orange)
                }
            }
        } header: { Text("iCloud Drive backup") } footer: {
            Text("Choose a folder in iCloud Drive, for example iCloud Drive › Subvelle. After every change, Subvelle saves “\(BackupPlan.latestFileName)” there and keeps \(BackupPlan.snapshotsKept) daily copies. iCloud Drive keeps them safe and available on your other devices. To restore, use Import backup. This is a backup, not live sync between devices.")
        }
        .confirmationDialog("Turn off automatic backup? Existing backup files stay in the folder.", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Turn off", role: .destructive) { store.stopAutoBackup() }
        }
    }
}

struct AboutSubspaceView: View {
    var body: some View {
        List {
            Section {
                Label { Text("Subvelle").font(.title2.bold()) } icon: { Image("SubvelleMark").resizable().scaledToFit().frame(width: 34, height: 34) }
                Text("Clarity for every recurring payment.")
            }
            Section("Tracking, on your terms") {
                Text("Subvelle tracks your subscriptions locally. It does not connect to banks or cancel services. Pausing or canceling a record changes your tracking only.")
                Text("Monthly and weekly averages normalize your current commitments. Calendar totals reflect scheduled charges, while past charts are reconstructed estimates.")
            }
        }.navigationTitle("About").navigationBarTitleDisplayMode(.inline)
    }
}
struct PrivacyDetailsView: View {
    var body: some View {
        List {
            Section("Local by design") {
                Text("Financial records stay in the app’s SwiftData database. No account, advertising SDK, or third-party tracking is used. Device backups may include app data according to your iOS settings.")
            }
            Section("Exchange rates") {
                Text("Subvelle makes two kinds of network request: public central-bank reference rates from Frankfurter, and, only when you tap Check for updates, GitHub’s public list of Subvelle releases. Your subscriptions are never included. Weekends and holidays use the most recent published rates. Unsupported pairs remain visible in their original currency and are excluded from converted totals.")
                if let url = URL(string: "https://frankfurter.dev") { Link("Frankfurter exchange rates", destination: url) }
            }
            Section("Backups") {
                Text("JSON exports contain readable financial data, including archived records. Store and share them carefully. Import is validated before merging and requires confirmation.")
                Text("Automatic backups are written only to the folder you choose. If it is in iCloud Drive, Apple’s iCloud Drive syncs those files under your Apple Account; Subvelle itself does not upload anything.")
            }
            Section("Reminders") {
                Text("Renewal alerts are local notifications. iOS limits the pending queue; Subvelle schedules the earliest 60 reminders within two years and replenishes them when you open the app or edit a plan. Delivery depends on your device’s notification and Focus settings.")
            }
        }.navigationTitle("Data & privacy").navigationBarTitleDisplayMode(.inline)
    }
}
