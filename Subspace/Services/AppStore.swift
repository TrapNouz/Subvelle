import Foundation
import Observation
import SwiftData
import SubspaceCore

@MainActor @Observable final class AppStore {
    @ObservationIgnored private var notificationTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let context: ModelContext
    /// A JSON copy of every subscription, rewritten after each change, in storage iOS never clears
    /// (Documents, visible in Files › On My iPhone › Subvelle). Nil disables it (tests, previews).
    private let safetyCopyURL: URL?
    /// Keychain account for a second safety copy, kept by iOS even if the app's files are wiped.
    private let keychainKey: String?
    nonisolated static var safetyCopyLocation: URL { URL.documentsDirectory.appendingPathComponent("Subvelle Backup.json") }
    private(set) var records: [SubscriptionRecord] = [] { didSet { refreshDerived() } }
    var error: String?
    var notificationMessage: String?
    private(set) var rates = ExchangeRates(rates: [:], updatedAt: .distantPast) { didSet { refreshDerived() } }
    private(set) var refreshingRates = false
    @ObservationIgnored private var backupTask: Task<Void, Never>?
    /// Display name of the automatic-backup folder; nil when automatic backup is off.
    private(set) var backupFolderName: String?
    /// Last completed backup of any kind: automatic, or an exported file.
    private(set) var lastBackup: Date?
    /// Why the most recent automatic backup failed; nil when it succeeded.
    private(set) var backupProblem: String?
    private(set) var backingUp = false
    var currency: String { didSet { defaults.set(currency, forKey: "reportingCurrency"); refreshDerived() } }
    var appearance: String { didSet { defaults.set(appearance, forKey: "appearance") } }
    var remindersEnabled: Bool { didSet { defaults.set(remindersEnabled, forKey: "remindersEnabled") } }
    var defaultReminder: Int { didSet { defaults.set(defaultReminder, forKey: "defaultReminder") } }
    init(container: ModelContainer, defaults: UserDefaults = .standard, safetyCopyURL: URL? = nil, keychainKey: String? = nil) {
        self.defaults = defaults
        self.safetyCopyURL = safetyCopyURL
        self.keychainKey = keychainKey
        context = ModelContext(container)
        context.autosaveEnabled = false
        currency = defaults.string(forKey: "reportingCurrency") ?? "CAD"
        appearance = defaults.string(forKey: "appearance") ?? "dark"
        remindersEnabled = defaults.bool(forKey: "remindersEnabled")
        defaultReminder = defaults.object(forKey: "defaultReminder") as? Int ?? 3
        backupFolderName = defaults.data(forKey: "backupBookmark") == nil ? nil : defaults.string(forKey: "backupFolderName")
        lastBackup = defaults.object(forKey: "lastBackup") as? Date
        if let cache = defaults.data(forKey: "exchangeRates") {
            do { rates = try JSONDecoder().decode(ExchangeRates.self, from: cache) }
            catch { self.error = "The exchange-rate cache could not be read. Refresh rates to restore conversions." }
        }
        reload()
        refreshDerived()
        restoreFromSafetyCopyIfNeeded()
    }

    /// If the database comes back empty while a safety copy still holds subscriptions, the database
    /// was lost (deleting everything by hand also empties the copies): restore it.
    /// Otherwise refresh the copies, so people updating from an older version get them right away.
    private func restoreFromSafetyCopyIfNeeded() {
        guard error == nil else { return }
        guard records.isEmpty else { writeSafetyCopy(); return }
        for (data, place) in safetyCopies() {
            guard let backup = try? JSONDecoder().decode(Backup.self, from: data),
                  let restored = try? backup.validated() else { continue }
            guard !restored.isEmpty else { return } // the newest readable copy says "no subscriptions"
            do {
                let count = try importBackup(data)
                error = "Subvelle found your data missing and restored \(count) subscriptions from its \(place)."
            } catch {
                self.error = "Your subscriptions are missing and could not be restored automatically. Use Settings › Import backup. \(error.localizedDescription)"
            }
            return
        }
    }
    private func safetyCopies() -> [(Data, String)] {
        var copies: [(Data, String)] = []
        if let url = safetyCopyURL, let data = try? Data(contentsOf: url) { copies.append((data, "safety copy in Files")) }
        if let key = keychainKey, let data = SafetyKeychain.read(account: key) { copies.append((data, "safety copy in the keychain")) }
        return copies
    }
    /// Rewrites both safety copies; small, atomic, and done right after each successful change.
    private func writeSafetyCopy() {
        guard let data = try? backupData() else { return }
        if let url = safetyCopyURL {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic])
        }
        if let key = keychainKey { SafetyKeychain.write(data, account: key) }
    }
    var visible: [SubscriptionRecord] { records.filter { !$0.archived } }
    /// Totals and the next payment for each plan. Stored and recomputed only when records, rates,
    /// currency or the day change, instead of on every read (screens read them many times per update).
    private(set) var summary = FinancialSummary(records: [], reportingCurrency: "CAD", rates: ExchangeRates(rates: [:]))
    private(set) var upcoming: [Payment] = []
    /// Recomputes `summary` and `upcoming`; also called when the app returns to the foreground,
    /// so "Today", next payments and active plans are right after midnight.
    func refreshDerived() {
        summary = FinancialSummary(records: records, reportingCurrency: currency, rates: rates)
        let engine = RecurrenceEngine()
        upcoming = records.compactMap { engine.nextPayment($0) }.sorted { $0.date < $1.date }
    }
    func money(_ amount: Decimal) -> String { Money.format(amount, currency: currency) }
    func converted(_ record: SubscriptionRecord) -> Decimal? { rates.convert(record.amount, from: record.currency, to: currency) }
    func payments(in range: DateInterval) -> [Payment] {
        records.flatMap { RecurrenceEngine().payments($0, in: range) }.sorted { $0.date < $1.date }
    }
    func total(_ payments: [Payment]) -> Decimal { payments.reduce(0) { $0 + (converted($1.subscription) ?? 0) } }
    func reload() {
        do {
            let entities = try context.fetch(FetchDescriptor<StoredSubscription>())
            records = try entities.map { try JSONDecoder().decode(SubscriptionRecord.self, from: $0.payload) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch { self.error = "Your subscriptions could not be loaded. The stored data has been preserved. \(error.localizedDescription)" }
    }
    func save(_ record: SubscriptionRecord) throws {
        try record.validate()
        do {
            let entities = try context.fetch(FetchDescriptor<StoredSubscription>())
            if let existing = entities.first(where: { $0.id == record.id }) { existing.payload = try JSONEncoder().encode(record) }
            else { context.insert(try StoredSubscription(record: record)) }
            try context.save()
        } catch { context.rollback(); throw error }
        reload()
        writeSafetyCopy(); scheduleNotifications(); scheduleAutoBackup()
    }
    func delete(_ record: SubscriptionRecord) throws {
        do {
            for entity in try context.fetch(FetchDescriptor<StoredSubscription>()) where entity.id == record.id { context.delete(entity) }
            try context.save()
        } catch { context.rollback(); throw error }
        reload(); writeSafetyCopy(); scheduleNotifications(); scheduleAutoBackup()
    }
    func importBackup(_ data: Data) throws -> Int {
        guard data.count <= 20_000_000 else { throw DataError.invalid("Backup exceeds the 20 MB import limit.") }
        let backup = try JSONDecoder().decode(Backup.self, from: data)
        let imported = try backup.validated()
        do {
            let entities = try context.fetch(FetchDescriptor<StoredSubscription>())
            let existing = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
            for record in imported {
                if let entity = existing[record.id] { entity.payload = try JSONEncoder().encode(record) }
                else { context.insert(try StoredSubscription(record: record)) }
            }
            try context.save()
        } catch { context.rollback(); throw error }
        reload(); writeSafetyCopy(); scheduleNotifications(); scheduleAutoBackup(); return imported.count
    }
    /// Reads and validates a backup picked in Files without changing anything; returns its bytes and
    /// record count. Opens the picker's security scope and uses a coordinated read, so a file that
    /// lives only in iCloud Drive is downloaded first. Blocking: call off the main actor.
    nonisolated static func readBackupFile(at url: URL) throws -> (Data, Int) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Data, any Error> = .failure(DataError.invalid("The backup file could not be read."))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readable in
            result = Result {
                let size = try readable.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 20_000_000 else { throw DataError.invalid("Backup exceeds the 20 MB import limit.") }
                return try Data(contentsOf: readable)
            }
        }
        if let coordinationError { throw coordinationError }
        let data = try result.get()
        let backup: Backup
        do { backup = try JSONDecoder().decode(Backup.self, from: data) }
        catch { throw DataError.invalid("This file is not a Subvelle backup. Choose a file exported from Subvelle, such as “\(BackupPlan.latestFileName)”.") }
        return (data, try backup.validated().count)
    }
    func backupData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Backup(subscriptions: records))
    }
    /// `silent` is used for the automatic launch refresh: offline launches keep cached rates without an alert.
    func refreshRates(silent: Bool = false) async {
        guard !refreshingRates else { return }
        refreshingRates = true
        defer { refreshingRates = false }
        do {
            let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=USD")
            guard let url else { throw DataError.invalid("Invalid exchange-rate URL.") }
            var request = URLRequest(url: url); request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw DataError.invalid("Exchange-rate provider is unavailable.") }
            struct Response: Decodable { let base: String; let date: String; let rates: [String: Decimal] }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"
            guard decoded.base == "USD", !decoded.rates.isEmpty, decoded.rates.values.allSatisfy({ $0 > 0 }), let date = formatter.date(from: decoded.date) else { throw DataError.invalid("Invalid exchange-rate response.") }
            let refreshed = ExchangeRates(base: decoded.base, rates: decoded.rates, updatedAt: date)
            defaults.set(try JSONEncoder().encode(refreshed), forKey: "exchangeRates")
            rates = refreshed
        } catch { if !silent { self.error = "Rates could not be refreshed. Cached rates remain available. \(error.localizedDescription)" } }
    }
    // MARK: Automatic folder backup (iCloud Drive)

    /// Starts automatic backups into a folder returned by the folder picker, writing one immediately.
    func setBackupFolder(_ folder: URL) async {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        do {
            defaults.set(try BackupWriter.bookmarkData(for: folder), forKey: "backupBookmark")
            defaults.set(folder.lastPathComponent, forKey: "backupFolderName")
            backupFolderName = folder.lastPathComponent
            backupProblem = nil
        } catch {
            backupProblem = "Subvelle could not keep access to that folder. Choose a folder in iCloud Drive or On My iPhone. \(error.localizedDescription)"
            return
        }
        await backUpNow()
    }
    func stopAutoBackup() {
        backupTask?.cancel()
        defaults.removeObject(forKey: "backupBookmark"); defaults.removeObject(forKey: "backupFolderName")
        backupFolderName = nil; backupProblem = nil
    }
    /// Records a manual export, which also counts as a recent backup.
    func markExported() { recordBackup() }
    /// Launch/foreground catch-up: back up when the last one is a day old or the previous attempt failed.
    func backUpIfDue() async {
        guard backupFolderName != nil, backupProblem != nil || BackupPlan.isDue(lastBackup: lastBackup) else { return }
        await backUpNow()
    }
    /// Writes the current records to the backup folder. Failures are reported in `backupProblem`
    /// (shown in Settings) rather than as an alert, because backups usually run in the background.
    func backUpNow() async {
        guard let bookmark = defaults.data(forKey: "backupBookmark"), !backingUp else { return }
        // Never replace the last good backup with an empty one (for example after storage loss).
        guard !records.isEmpty else { return }
        backingUp = true
        defer { backingUp = false }
        do {
            let data = try backupData()
            let refreshed = try await Task.detached(priority: .utility) { try BackupWriter.write(data, bookmark: bookmark) }.value
            // The folder may have been turned off while the write ran.
            guard defaults.data(forKey: "backupBookmark") != nil else { return }
            if let refreshed { defaults.set(refreshed, forKey: "backupBookmark") }
            backupProblem = nil
            recordBackup()
        } catch {
            backupProblem = "The last automatic backup failed. \(error.localizedDescription)"
        }
    }
    private func recordBackup() {
        lastBackup = .now
        defaults.set(lastBackup, forKey: "lastBackup")
    }
    /// Coalesces bursts of edits (for example, an import) into one backup a moment later.
    private func scheduleAutoBackup() {
        guard backupFolderName != nil else { return }
        backupTask?.cancel()
        backupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            if self.backingUp { self.scheduleAutoBackup(); return }
            await self.backUpNow()
        }
    }
    func scheduleNotifications() {
        let records = records; let enabled = remindersEnabled
        let previous = notificationTask
        previous?.cancel()
        notificationTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            do { notificationMessage = try await ReminderService.reschedule(records: records, enabled: enabled) }
            catch is CancellationError { /* A newer schedule supersedes this one. */ }
            catch { notificationMessage = error.localizedDescription }
        }
    }
    func enableReminders() async {
        do {
            let allowed = try await ReminderService.requestAuthorization()
            remindersEnabled = allowed
            if !allowed { notificationMessage = "Notifications are disabled. Enable them in iOS Settings to receive renewal reminders."; return }
            scheduleNotifications()
        } catch { notificationMessage = error.localizedDescription }
    }
}
