import Foundation

public enum SubscriptionScope: String, CaseIterable, Sendable { case all = "All", active = "Active", paused = "Paused", canceled = "Canceled", archived = "Archived" }
public enum SubscriptionSort: String, CaseIterable, Sendable { case renewal = "Next renewal", amount = "Payment amount", name = "Name" }
public struct SubscriptionListQuery: Sendable {
    public var search = ""
    public var category: Category?
    public var scope: SubscriptionScope = .all
    public var sort: SubscriptionSort = .renewal
    public init() {}
    public func apply(to records: [SubscriptionRecord], reportingCurrency: String, rates: ExchangeRates, now: Date = .now) -> [SubscriptionRecord] {
        let filtered = records.filter { record in
            (scope == .archived ? record.archived : !record.archived) &&
            (scope == .all || scope == .archived || record.status.rawValue.capitalized == scope.rawValue) &&
            (category == nil || record.category == category) &&
            (search.isEmpty || record.name.localizedCaseInsensitiveContains(search) || record.notes.localizedCaseInsensitiveContains(search))
        }
        // Resolve recurrence/FX once per record, rather than inside the sorting comparator.
        let engine = RecurrenceEngine()
        let dates = Dictionary(uniqueKeysWithValues: filtered.map { ($0.id, engine.nextPayment($0, from: now)?.date ?? .distantFuture) })
        let amounts = Dictionary(uniqueKeysWithValues: filtered.map { ($0.id, rates.convert($0.amount, from: $0.currency, to: reportingCurrency) ?? -1) })
        return filtered.sorted { left, right in
            if sort == .renewal, dates[left.id] != dates[right.id] { return (dates[left.id] ?? .distantFuture) < (dates[right.id] ?? .distantFuture) }
            if sort == .amount, amounts[left.id] != amounts[right.id] { return (amounts[left.id] ?? -1) > (amounts[right.id] ?? -1) }
            let comparison = left.name.localizedCaseInsensitiveCompare(right.name)
            return comparison == .orderedSame ? left.id.uuidString < right.id.uuidString : comparison == .orderedAscending
        }
    }
}
