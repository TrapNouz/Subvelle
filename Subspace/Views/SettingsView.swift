import SwiftUI
import UIKit
import UniformTypeIdentifiers
import SubspaceCore

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw DataError.invalid("This backup file cannot be read.") }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var importing = false
    @State private var exporting = false
    @State private var document = BackupDocument()
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
                        do { document = BackupDocument(data: try store.backupData()); exporting = true }
                        catch { store.error = error.localizedDescription }
                    }.accessibilityIdentifier("exportBackup")
                    Button("Import backup", systemImage: "square.and.arrow.down") { importing = true }
                    if let result { Text(result).font(.caption).foregroundStyle(.secondary) }
                } header: { Text("Backup & restore") } footer: { Text("JSON backups include all plans. Import replaces matching IDs and preserves other plans. Export a recovery copy first.") }
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
                .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Subspace-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { outcome in
                    switch outcome { case .success: result = "Backup exported."; case .failure(let error): store.error = error.localizedDescription }
                }
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
            }
            Section("Reminders") {
                Text("Renewal alerts are local notifications. iOS limits the pending queue; Subspace schedules the earliest 60 reminders within two years and replenishes them when you open the app or edit a plan. Delivery depends on your device’s notification and Focus settings.")
            }
        }.navigationTitle("Data & privacy").navigationBarTitleDisplayMode(.inline)
    }
}
