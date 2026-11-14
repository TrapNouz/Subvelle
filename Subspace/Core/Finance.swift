import Foundation

public struct Payment: Identifiable, Sendable {
    public var subscription: SubscriptionRecord
    public var date: Date
    public var id: String { "\(subscription.id)-\(date.timeIntervalSince1970)" }
}
/// Occurrences are always calculated from the original anchor, never from a clamped previous date.
public struct RecurrenceEngine: Sendable {
    public var calendar: Calendar
    public init(calendar: Calendar = .current) { self.calendar = calendar }
    public func occurrence(_ record: SubscriptionRecord, index: Int) -> Date? {
        let interval = record.interval
        guard (1...1000).contains(interval.count), abs(index) < 1_000_000 else { return nil }
        let anchor = calendar.startOfDay(for: record.nextRenewal)
        let value = interval.count * index
        switch interval.unit {
        case .day: return calendar.date(byAdding: .day, value: value, to: anchor)
        case .week: return calendar.date(byAdding: .day, value: value * 7, to: anchor)
        case .month, .year:
            let months = value * (interval.unit == .year ? 12 : 1)
            var components = calendar.dateComponents([.era, .year, .month], from: anchor)
            components.day = 1
            guard let first = calendar.date(from: components), let target = calendar.date(byAdding: .month, value: months, to: first), let range = calendar.range(of: .day, in: .month, for: target) else { return nil }
            return calendar.date(byAdding: .day, value: min(calendar.component(.day, from: anchor), range.count) - 1, to: target)
        }
    }
    private func estimatedIndex(_ record: SubscriptionRecord, date: Date) -> Int {
        let anchor = calendar.startOfDay(for: record.nextRenewal)
        let interval = record.interval
        guard interval.count > 0 else { return 0 }
        switch interval.unit {
        case .day: return (calendar.dateComponents([.day], from: anchor, to: date).day ?? 0) / interval.count
        case .week: return (calendar.dateComponents([.day], from: anchor, to: date).day ?? 0) / (7 * interval.count)
        case .month: return (calendar.dateComponents([.month], from: anchor, to: date).month ?? 0) / interval.count
        case .year: return (calendar.dateComponents([.year], from: anchor, to: date).year ?? 0) / interval.count
        }
    }
    public func payments(_ record: SubscriptionRecord, in range: DateInterval) -> [Payment] {
        guard record.status == .active, !record.archived, record.interval.count > 0 else { return [] }
        let lower = max(range.start, max(calendar.startOfDay(for: record.startDate), record.trialEnd.map { calendar.startOfDay(for: $0) } ?? .distantPast))
        let end = record.endDate.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) } ?? range.end
        let upper = min(range.end, end)
        guard lower < upper else { return [] }
        var index = estimatedIndex(record, date: lower) - 2
        var result: [Payment] = []
        // A bounded range keeps corrupt data from creating an unbounded loop.
        for _ in 0..<40000 {
            guard let date = occurrence(record, index: index) else { break }
            if date >= upper { break }
            if date >= lower { result.append(Payment(subscription: record, date: date)) }
            index += 1
        }
        return result
    }
    public func nextPayment(_ record: SubscriptionRecord, from date: Date = .now) -> Payment? {
        let start = calendar.startOfDay(for: date)
        guard record.status == .active, !record.archived else { return nil }
        let lower = max(start, max(calendar.startOfDay(for: record.startDate), record.trialEnd.map { calendar.startOfDay(for: $0) } ?? .distantPast))
        let initial = estimatedIndex(record, date: lower) - 2
        for index in initial..<(initial + 8) {
            guard let date = occurrence(record, index: index) else { continue }
            if date >= lower {
                if let end = record.endDate, date > calendar.startOfDay(for: end) { return nil }
                return Payment(subscription: record, date: date)
            }
        }
        return nil
    }
}
public struct ExchangeRates: Codable, Sendable {
    public var base: String
    public var rates: [String: Decimal]
    public var updatedAt: Date
    public init(base: String = "USD", rates: [String: Decimal], updatedAt: Date = .now) { self.base = base; self.rates = rates; self.updatedAt = updatedAt }
    public func convert(_ amount: Decimal, from: String, to: String) -> Decimal? {
        if from == to { return amount }
        let source = from == base ? Decimal(1) : rates[from]
        let target = to == base ? Decimal(1) : rates[to]
        guard let source, let target, source > 0, target > 0 else { return nil }
        return amount / source * target
    }
    public var isStale: Bool { Date.now.timeIntervalSince(updatedAt) > 86400 * 4 }
}
public struct FinancialSummary: Sendable {
    public var monthly: Decimal = 0
    public var annual: Decimal = 0
    public var weekly: Decimal = 0
    public var activeCount = 0
    public var missingCurrencies: Set<String> = []
    public init(records: [SubscriptionRecord], reportingCurrency: String, rates: ExchangeRates, now: Date = .now) {
        for record in records where record.status == .active && !record.archived && (record.endDate.map { $0 >= Calendar.current.startOfDay(for: now) } ?? true) {
            activeCount += 1
            guard let converted = rates.convert(record.amount, from: record.currency, to: reportingCurrency) else { missingCurrencies.insert(record.currency); continue }
            annual += converted * record.interval.periodsPerYear
        }
        monthly = annual / 12
        weekly = annual * 7 / (Decimal(3652425) / 10000)
    }
}
public enum Money {
    /// Strictly accepts localized decimal input, with no grouping or trailing text.
    public static func parse(_ text: String, locale: Locale = .current) -> Decimal? {
        let separator = locale.decimalSeparator ?? "."
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: separator, with: ".")
        guard normalized.count <= 38, normalized.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }
    public static func format(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount) \(currency)"
    }
}
