import Foundation
import Observation
import SwiftData
import SubspaceCore

@MainActor @Observable final class AppStore {
    @ObservationIgnored private var notificationTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let context: ModelContext
    private(set) var records: [SubscriptionRecord] = []
    var error: String?
    var notificationMessage: String?
    private(set) var rates = ExchangeRates(rates: [:], updatedAt: .distantPast)
    private(set) var refreshingRates = false
    var currency: String { didSet { defaults.set(currency, forKey: "reportingCurrency") } }
    var appearance: String { didSet { defaults.set(appearance, forKey: "appearance") } }
    var remindersEnabled: Bool { didSet { defaults.set(remindersEnabled, forKey: "remindersEnabled") } }
    var defaultReminder: Int { didSet { defaults.set(defaultReminder, forKey: "defaultReminder") } }
    init(container: ModelContainer, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        context = ModelContext(container)
        context.autosaveEnabled = false
        currency = defaults.string(forKey: "reportingCurrency") ?? "CAD"
        appearance = defaults.string(forKey: "appearance") ?? "dark"
        remindersEnabled = defaults.bool(forKey: "remindersEnabled")
        defaultReminder = defaults.object(forKey: "defaultReminder") as? Int ?? 3
        if let cache = defaults.data(forKey: "exchangeRates") {
            do { rates = try JSONDecoder().decode(ExchangeRates.self, from: cache) }
            catch { self.error = "The exchange-rate cache could not be read. Refresh rates to restore conversions." }
        }
        reload()
    }
    var visible: [SubscriptionRecord] { records.filter { !$0.archived } }
    var summary: FinancialSummary { FinancialSummary(records: records, reportingCurrency: currency, rates: rates) }
    var upcoming: [Payment] { records.compactMap { RecurrenceEngine().nextPayment($0) }.sorted { $0.date < $1.date } }
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
        scheduleNotifications()
    }
    func delete(_ record: SubscriptionRecord) throws {
        do {
            for entity in try context.fetch(FetchDescriptor<StoredSubscription>()) where entity.id == record.id { context.delete(entity) }
            try context.save()
        } catch { context.rollback(); throw error }
        reload(); scheduleNotifications()
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
        reload(); scheduleNotifications(); return imported.count
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
