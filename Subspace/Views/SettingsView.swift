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
    @State private var importing = false
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
                    NavigationLink("About Subspace") { AboutSubspaceView() }
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
                } header: { Text("Notifications") } footer: { Text("Delivered at 9 AM local time. Open Subspace periodically to refresh the queue. Defaults apply to new plans.") }
                Section {
                    Button("Export backup", systemImage: "square.and.arrow.up") {
                        do { document = BackupExport(data: try store.backupData()); exporting = true }
                        catch { store.error = error.localizedDescription }
                    }.accessibilityIdentifier("exportBackup")
                    Button("Import backup", systemImage: "square.and.arrow.down") { importing = true }
                    if let result { Text(result).font(.caption).foregroundStyle(.secondary) }
                } header: { Text("Backup & restore") } footer: { Text("JSON backups include all plans. Import replaces matching IDs and preserves other plans. Export a recovery copy first.") }
                AutoBackupSection()
                Section("Privacy & information") {
                    Label("On-device storage", systemImage: "internaldrive")
                    Label("No accounts, ads, or tracking", systemImage: "hand.raised")
                    NavigationLink("Data & privacy details") { PrivacyDetailsView() }
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    Text("Built for a clearer financial orbit.").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("settingsBottom")
                }
            }.navigationTitle("Settings")
                .accessibilityIdentifier("settingsScroll")
                .scrollEdgeEffectStyle(.hard, for: .bottom)
                .subscriptionToolbar()
                .fileExporter(isPresented: $exporting, item: document, contentTypes: [.json], defaultFilename: "Subspace-\(Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash)))", onCompletion: { outcome in
                    // ISO 8601 formatting defaults to UTC; use the local day so evening exports are not dated tomorrow.
                    switch outcome { case .success: result = "Backup exported."; store.markExported(); case .failure(let error): store.error = error.localizedDescription }
                })
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { outcome in
                    do {
                        let url = try outcome.get()
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 20_000_000 else { throw DataError.invalid("Backup exceeds the 20 MB import limit.") }
                        let data = try Data(contentsOf: url)
                        importCount = try JSONDecoder().decode(Backup.self, from: data).validated().count
                        pendingImport = data; confirmation = true
                    } catch { store.error = error.localizedDescription }
                }
                .confirmationDialog("Import \(importCount) subscriptions? Matching IDs will be replaced. Export a backup first if needed.", isPresented: $confirmation, titleVisibility: .visible) {
                    Button("Merge backup") {
                        guard let pendingImport else { return }
                        do { let count = try store.importBackup(pendingImport); result = "Imported \(count) subscriptions."; self.pendingImport = nil }
                        catch { store.error = error.localizedDescription }
                    }
                    Button("Cancel", role: .cancel) { pendingImport = nil }
                }
        }
    }
}

/// Automatic backups into a folder the user picks, typically in iCloud Drive. A separate view owns its
/// own folder picker, so it does not compete with the JSON import picker on the Settings form.
struct AutoBackupSection: View {
    @Environment(AppStore.self) private var store
    @State private var choosingFolder = false
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
                Button("Change folder", systemImage: "folder.badge.gearshape") { choosingFolder = true }
                Button("Turn off automatic backup", systemImage: "icloud.slash", role: .destructive) { confirmingStop = true }
            } else {
                Button("Choose backup folder", systemImage: "icloud.and.arrow.up") { choosingFolder = true }
                    .accessibilityIdentifier("chooseBackupFolder")
                if let problem = store.backupProblem {
                    Label(problem, systemImage: "exclamationmark.icloud").font(.caption).foregroundStyle(.orange)
                }
            }
        } header: { Text("iCloud Drive backup") } footer: {
            Text("Choose a folder in iCloud Drive, for example iCloud Drive › Subspace. After every change, Subspace saves “\(BackupPlan.latestFileName)” there and keeps \(BackupPlan.snapshotsKept) daily copies. iCloud Drive keeps them safe and available on your other devices. To restore, use Import backup. This is a backup, not live sync between devices.")
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { outcome in
            switch outcome {
            case .success(let folder): Task { await store.setBackupFolder(folder) }
            case .failure(let error): store.error = error.localizedDescription
            }
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
                Label("Subspace", systemImage: "circle.hexagongrid").font(.title2.bold())
                Text("Clarity for every recurring payment.")
            }
            Section("Tracking, on your terms") {
                Text("Subspace tracks your subscriptions locally. It does not connect to banks or cancel services. Pausing or canceling a record changes your tracking only.")
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
                Text("The only network request fetches public central-bank reference rates from Frankfurter. Your subscriptions are never included. Weekends and holidays use the most recent published rates. Unsupported pairs remain visible in their original currency and are excluded from converted totals.")
                if let url = URL(string: "https://frankfurter.dev") { Link("Frankfurter exchange rates", destination: url) }
            }
            Section("Backups") {
                Text("JSON exports contain readable financial data, including archived records. Store and share them carefully. Import is validated before merging and requires confirmation.")
                Text("Automatic backups are written only to the folder you choose. If it is in iCloud Drive, Apple’s iCloud Drive syncs those files under your Apple Account; Subspace itself does not upload anything.")
            }
            Section("Reminders") {
                Text("Renewal alerts are local notifications. iOS limits the pending queue; Subspace schedules the earliest 60 reminders within two years and replenishes them when you open the app or edit a plan. Delivery depends on your device’s notification and Focus settings.")
            }
        }.navigationTitle("Data & privacy").navigationBarTitleDisplayMode(.inline)
    }
}
