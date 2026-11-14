import Foundation
import Testing
@testable import SubspaceCore

@Suite("Subscription list behavior") struct SubscriptionListQueryTests {
    let rates = ExchangeRates(rates: ["CAD": Decimal(135) / 100])
    @Test("Amounts sort after conversion, with missing rates last") func convertedPaymentSorting() {
        let cad = SubscriptionRecord(name: "CAD", amount: 12, currency: "CAD")
        let usd = SubscriptionRecord(name: "USD", amount: 10, currency: "USD")
        let unknown = SubscriptionRecord(name: "Unavailable", amount: 10000, currency: "JPY")
        var query = SubscriptionListQuery(); query.sort = .amount
        #expect(query.apply(to: [unknown, cad, usd], reportingCurrency: "CAD", rates: rates).map(\.id) == [usd.id, cad.id, unknown.id])
    }
    @Test("Renewals sort by their next occurrence, not a stale anchor") func renewalSorting() {
        let now = Date.now
        let first = SubscriptionRecord(name: "Tomorrow", amount: 10, startDate: now.addingTimeInterval(-86400), nextRenewal: now.addingTimeInterval(86400))
        let second = SubscriptionRecord(name: "Later", amount: 10, startDate: now, nextRenewal: now.addingTimeInterval(86400 * 5))
        let paused = SubscriptionRecord(name: "Paused", amount: 10, status: .paused)
        var query = SubscriptionListQuery(); query.sort = .renewal
        #expect(query.apply(to: [paused, second, first], reportingCurrency: "CAD", rates: rates, now: now).map(\.id) == [first.id, second.id, paused.id])
    }
    @Test("Scope and category filters preserve archived data", arguments: SubscriptionScope.allCases)
    func filters(scope: SubscriptionScope) {
        let records = [SubscriptionRecord(name: "Active", amount: 10, category: .music), SubscriptionRecord(name: "Paused", amount: 10, category: .music, status: .paused), SubscriptionRecord(name: "Canceled", amount: 10, category: .music, status: .canceled), SubscriptionRecord(name: "Archived", amount: 10, category: .music, archived: true)]
        var query = SubscriptionListQuery(); query.scope = scope; query.category = .music
        let result = query.apply(to: records, reportingCurrency: "CAD", rates: rates)
        #expect(result.count == (scope == .all ? 3 : 1))
        #expect(result.allSatisfy { scope == .archived ? $0.archived : !$0.archived })
        #expect(records.count == 4)
    }
    @Test("Search includes notes and name sorting is case insensitive") func searching() {
        let a = SubscriptionRecord(name: "alpha", amount: 10, notes: "Work")
        let b = SubscriptionRecord(name: "Beta", amount: 10)
        var query = SubscriptionListQuery(); query.sort = .name
        #expect(query.apply(to: [b,a], reportingCurrency: "CAD", rates: rates).map(\.name) == ["alpha", "Beta"])
        query.search = "WORK"
        #expect(query.apply(to: [a,b], reportingCurrency: "CAD", rates: rates).map(\.id) == [a.id])
    }
}
