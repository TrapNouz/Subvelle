import Foundation

public enum BillingUnit: String, Codable, CaseIterable, Sendable { case day, week, month, year }
public struct BillingInterval: Codable, Equatable, Sendable {
    public var count: Int
    public var unit: BillingUnit
    public init(count: Int, unit: BillingUnit) { self.count = count; self.unit = unit }
    public static let weekly = Self(count: 1, unit: .week)
    public static let biweekly = Self(count: 2, unit: .week)
    public static let monthly = Self(count: 1, unit: .month)
    public static let quarterly = Self(count: 3, unit: .month)
    public static let semiannual = Self(count: 6, unit: .month)
    public static let annual = Self(count: 1, unit: .year)
    public static let standard: [Self] = [.weekly, .biweekly, .monthly, .quarterly, .semiannual, .annual]
    public var label: String {
        switch self {
        case .weekly: "Weekly"
        case .biweekly: "Every two weeks"
        case .monthly: "Monthly"
        case .quarterly: "Every three months"
        case .semiannual: "Every six months"
        case .annual: "Annually"
        default: "Every \(count) \(unit.rawValue)\(count == 1 ? "" : "s")"
        }
    }
    public var periodsPerYear: Decimal {
        guard count > 0 else { return 0 }
        switch unit {
        case .day: return (Decimal(3652425) / 10000) / Decimal(count)
        case .week: return (Decimal(3652425) / 10000) / Decimal(7 * count)
        case .month: return 12 / Decimal(count)
        case .year: return 1 / Decimal(count)
        }
    }
}
public enum SubscriptionStatus: String, Codable, CaseIterable, Sendable { case active, paused, canceled }
public enum Category: String, Codable, CaseIterable, Sendable {
    case streaming = "Streaming", music = "Music", ai = "AI", gaming = "Gaming", privacy = "Privacy & VPN", productivity = "Productivity", cloud = "Cloud", fitness = "Fitness", education = "Education", news = "News", hosting = "Hosting", developer = "Developer", other = "Other"
    public var symbol: String {
        switch self {
        case .streaming: "play.tv.fill"
        case .music: "music.note"
        case .ai: "sparkles"
        case .gaming: "gamecontroller.fill"
        case .privacy: "lock.shield.fill"
        case .productivity: "checkmark.seal.fill"
        case .cloud: "cloud.fill"
        case .fitness: "figure.run"
        case .education: "graduationcap.fill"
        case .news: "newspaper.fill"
        case .hosting: "server.rack"
        case .developer: "curlybraces"
        case .other: "square.grid.2x2.fill"
        }
    }
}
public struct SubscriptionRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var amount: Decimal
    public var currency: String
    public var interval: BillingInterval
    public var startDate: Date
    public var nextRenewal: Date
    public var category: Category
    public var notes: String
    public var trialEnd: Date?
    public var status: SubscriptionStatus
    public var endDate: Date?
    public var reminderDays: Int?
    public var archived: Bool
    public init(id: UUID = UUID(), name: String = "", symbol: String = "creditcard.fill", amount: Decimal = 0, currency: String = "CAD", interval: BillingInterval = .monthly, startDate: Date = .now, nextRenewal: Date = .now, category: Category = .other, notes: String = "", trialEnd: Date? = nil, status: SubscriptionStatus = .active, endDate: Date? = nil, reminderDays: Int? = 3, archived: Bool = false) {
        self.id = id; self.name = name; self.symbol = symbol; self.amount = amount; self.currency = currency; self.interval = interval; self.startDate = startDate; self.nextRenewal = nextRenewal; self.category = category; self.notes = notes; self.trialEnd = trialEnd; self.status = status; self.endDate = endDate; self.reminderDays = reminderDays; self.archived = archived
    }
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120 else { throw DataError.invalid("Enter a service name of 1–120 characters.") }
        guard !amount.isNaN, amount > 0, amount <= Decimal(1_000_000_000_000) else { throw DataError.invalid("Enter an amount greater than zero and no more than one trillion.") }
        guard currency.count == 3, Locale.commonISOCurrencyCodes.contains(currency) else { throw DataError.invalid("Choose a valid ISO currency.") }
        guard (1...1000).contains(interval.count) else { throw DataError.invalid("Billing intervals must be between 1 and 1,000.") }
        guard nextRenewal >= Calendar.current.startOfDay(for: startDate), endDate.map({ $0 >= startDate }) ?? true else { throw DataError.invalid("Renewal and end dates must be on or after the start date.") }
        if let trialEnd {
            guard trialEnd >= Calendar.current.startOfDay(for: startDate), Calendar.current.startOfDay(for: trialEnd) <= Calendar.current.startOfDay(for: nextRenewal) else { throw DataError.invalid("Trial end must be between the start date and the first paid renewal.") }
        }
        guard reminderDays.map({ [1,3,7,14].contains($0) }) ?? true else { throw DataError.invalid("Unsupported reminder interval.") }
    }
}
public enum DataError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): message } }
}
public struct Backup: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var exportedAt: Date = .now
    public var subscriptions: [SubscriptionRecord]
    public init(subscriptions: [SubscriptionRecord]) { self.subscriptions = subscriptions }
    public func validated() throws -> [SubscriptionRecord] {
        guard schemaVersion == 1 else { throw DataError.invalid("This backup version is not supported. Update Subspace before importing.") }
        guard subscriptions.count <= 10000, Set(subscriptions.map(\.id)).count == subscriptions.count else { throw DataError.invalid("Backup contains too many records or duplicate IDs.") }
        try subscriptions.forEach { try $0.validate() }
        return subscriptions
    }
}
