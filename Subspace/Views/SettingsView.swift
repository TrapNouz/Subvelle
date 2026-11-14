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
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "circle.hexagongrid.fill").font(.largeTitle).foregroundStyle(Color.spaceAccent)
                        VStack(alignment: .leading, spacing: 5) { Text("Subspace").font(.title2.bold()); Text("Clarity for every recurring payment.").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 12)
                }
                Section {
                    CurrencyPicker(selection: $store.currency, title: "Reporting currency")
                    if store.rates.updatedAt == .distantPast { Text("No exchange rates cached yet.").foregroundStyle(.secondary) }
                    else { LabeledContent("Rates as of", value: store.rates.updatedAt.formatted(date: .abbreviated, time: .omitted)) }
                    if store.rates.isStale { Label("Rates may be out of date", systemImage: "clock.badge.exclamationmark").font(.caption).foregroundStyle(.orange) }
                    Button { Task { await store.refreshRates() } } label: {
                        HStack { Text("Refresh exchange rates"); Spacer(); if store.refreshingRates { ProgressView() } else { Image(systemName: "arrow.clockwise") } }
                    }.disabled(store.refreshingRates)
                    if let url = URL(string: "https://frankfurter.dev") { Link("About Frankfurter exchange rates", destination: url) }
                } header: { Text("Currency & conversion") } footer: { Text("Frankfurter publishes reference rates from central banks. Rates are cached for offline use. Weekends and holidays use the most recent published rates. Unsupported currency pairs are excluded from converted totals and flagged; original amounts remain available. Only the rate request leaves your device; your subscriptions are never sent.") }
                Section("Appearance") {
                    Picker("Theme", selection: $store.appearance) { Text("Dark").tag("dark"); Text("Follow system").tag("system") }
                }
                Section {
                    Toggle("Renewal notifications", isOn: Binding(get: { store.remindersEnabled }, set: { enabled in
                        if enabled { Task { await store.enableReminders() } }
                        else { store.remindersEnabled = false; store.scheduleNotifications() }
                    }))
                    Picker("Default reminder", selection: $store.defaultReminder) { ForEach([1,3,7,14], id: \.self) { Text("\($0) days before").tag($0) } }
                    if let message = store.notificationMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                    Button("Open iOS notification settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                } header: { Text("Reminders") } footer: { Text("Reminders arrive at 9 AM local time. The default applies to new subscriptions; edit existing subscriptions to change their reminder. Open Subspace periodically to refresh iOS’s limited notification queue.") }
                Section {
                    Button("Export JSON backup", systemImage: "square.and.arrow.up") {
                        do { document = BackupDocument(data: try store.backupData()); exporting = true }
                        catch { store.error = error.localizedDescription }
                    }
                    Button("Import JSON backup", systemImage: "square.and.arrow.down") { importing = true }
                    if let result { Text(result).font(.caption).foregroundStyle(.secondary) }
                } header: { Text("Your data") } footer: { Text("Import merges records by ID. Matching subscriptions are replaced and other subscriptions are preserved. Export before importing to keep a recovery copy. Backup files contain your financial data in readable form; store and share them carefully.") }
                Section("Privacy") {
                    Label("Stored locally with SwiftData", systemImage: "internaldrive")
                    Label("No account, ads, or tracking", systemImage: "hand.raised.fill")
                    Label("Works offline with cached rates", systemImage: "wifi.slash")
                    Text("Subspace does not connect to banks or cancel services. Pausing or canceling a record changes your tracking only. Device backups may include app data according to your iOS settings.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    Text("Built for a clearer financial orbit.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings")
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
