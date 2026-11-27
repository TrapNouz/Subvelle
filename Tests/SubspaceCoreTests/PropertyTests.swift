import Foundation
import Testing
@testable import SubspaceCore

/// Seeded random generator, so any failure is reproducible.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Invariants checked over hundreds of random subscriptions in a time zone with daylight saving.
@Suite("Property checks on random subscriptions") struct PropertyTests {
    static let zone = TimeZone(identifier: "America/Toronto")!
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = Self.zone; return c }

    func randomRecord(_ rng: inout SplitMix64) -> SubscriptionRecord {
        let cal = calendar
        let base = cal.date(from: DateComponents(year: 2022, month: 1, day: 1))!
        func day(_ offset: Int, hour: Int = 0) -> Date { cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: offset, to: base)!)! }
        let units: [BillingUnit] = [.day, .week, .month, .year]
        let unit = units[Int.random(in: 0..<4, using: &rng)]
        let count: Int = switch unit { case .day: Int.random(in: 1...45, using: &rng); case .week: Int.random(in: 1...13, using: &rng); case .month: Int.random(in: 1...18, using: &rng); case .year: Int.random(in: 1...3, using: &rng) }
        // Bias anchors toward month ends and Feb 29 to exercise clamping.
        let anchorChoices = [Int.random(in: 0...1500, using: &rng), 30, 58, 59, 789, 1155, 1186, 1520]
        let startOffset = anchorChoices[Int.random(in: 0..<anchorChoices.count, using: &rng)]
        let hour = Int.random(in: 0...23, using: &rng)
        let start = day(startOffset, hour: hour)
        let renewal = day(startOffset + Int.random(in: 0...90, using: &rng), hour: Int.random(in: 0...23, using: &rng))
        let trial: Date? = Bool.random(using: &rng) && Int.random(in: 0..<3, using: &rng) == 0 ? renewal : nil
        let end: Date? = Int.random(in: 0..<3, using: &rng) == 0 ? day(startOffset + Int.random(in: 0...1800, using: &rng)) : nil
        let amount = Decimal(Int.random(in: 1...99_999, using: &rng)) / 100
        return SubscriptionRecord(name: "R", amount: amount, currency: ["CAD", "USD", "EUR"][Int.random(in: 0..<3, using: &rng)],
                                  interval: BillingInterval(count: count, unit: unit), startDate: start, nextRenewal: renewal,
                                  trialEnd: trial, endDate: end)
    }

    /// The obvious, slow definition: every occurrence index near the window, filtered by the rules.
    func bruteForce(_ record: SubscriptionRecord, _ window: DateInterval, _ engine: RecurrenceEngine) -> [Date] {
        let cal = calendar
        let lower = max(window.start, cal.startOfDay(for: record.startDate), record.trialEnd.map { cal.startOfDay(for: $0) } ?? .distantPast)
        let upper = min(window.end, record.endDate.flatMap { cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: $0)) } ?? .distantFuture)
        let periodDays: Int = switch record.interval.unit { case .day: record.interval.count; case .week: 7 * record.interval.count; case .month: 28 * record.interval.count; case .year: 365 * record.interval.count }
        let spanDays = 8 * 366
        let reach = spanDays / periodDays + 3
        return (-reach...reach).compactMap { engine.occurrence(record, index: $0) }.filter { $0 >= lower && $0 < upper }.sorted()
    }

    @Test("Scheduled payments equal the brute-force definition, and windows split cleanly")
    func paymentsMatchDefinition() {
        var rng = SplitMix64(state: 20261127)
        let engine = RecurrenceEngine(calendar: calendar)
        let cal = calendar
        let a = cal.date(from: DateComponents(year: 2023, month: 3, day: 5))!
        let b = cal.date(from: DateComponents(year: 2025, month: 11, day: 2))!   // a DST change day
        let c = cal.date(from: DateComponents(year: 2027, month: 6, day: 30))!
        for _ in 0..<250 {
            let record = randomRecord(&rng)
            let whole = engine.payments(record, in: DateInterval(start: a, end: c)).map(\.date)
            #expect(whole == bruteForce(record, DateInterval(start: a, end: c), engine), "Schedule differs for \(record.interval) start \(record.startDate) anchor \(record.nextRenewal)")
            let split = engine.payments(record, in: DateInterval(start: a, end: b)).map(\.date) + engine.payments(record, in: DateInterval(start: b, end: c)).map(\.date)
            #expect(whole == split, "Splitting the window changed the schedule for \(record.interval)")
            #expect(zip(whole, whole.dropFirst()).allSatisfy { $0 < $1 }, "Payments must be strictly increasing")
            #expect(whole.allSatisfy { cal.startOfDay(for: $0) == $0 }, "Payments fall on local midnight")
        }
    }

    @Test("Next payment is the first scheduled payment from that day")
    func nextPaymentMatchesSchedule() {
        var rng = SplitMix64(state: 42)
        let engine = RecurrenceEngine(calendar: calendar)
        let cal = calendar
        let far = cal.date(from: DateComponents(year: 2040, month: 1, day: 1))!
        for _ in 0..<250 {
            let record = randomRecord(&rng)
            for offset in [0, 17, 400, 1111] {
                let today = cal.date(byAdding: .hour, value: 13, to: cal.date(byAdding: .day, value: offset, to: cal.date(from: DateComponents(year: 2023, month: 1, day: 1))!)!)!
                let expected = engine.payments(record, in: DateInterval(start: cal.startOfDay(for: today), end: far)).first?.date
                #expect(engine.nextPayment(record, from: today)?.date == expected, "nextPayment disagrees for \(record.interval) anchor \(record.nextRenewal) today \(today)")
            }
        }
    }

    @Test("Totals: monthly × 12 equals annual, weekly follows the mean year, conversion is consistent")
    func totalsAreConsistent() {
        var rng = SplitMix64(state: 7)
        let rates = ExchangeRates(rates: ["CAD": Decimal(string: "1.3712")!, "EUR": Decimal(string: "0.9214")!])
        let records = (0..<300).map { _ in randomRecord(&rng) }
        let summary = FinancialSummary(records: records, reportingCurrency: "CAD", rates: rates, now: calendar.date(from: DateComponents(year: 2024, month: 6, day: 1))!)
        let tolerance = Decimal(string: "0.000001")!
        #expect(abs(summary.monthly * 12 - summary.annual) < tolerance)
        #expect(abs(summary.weekly * Decimal(string: "365.2425")! / 7 - summary.annual) < tolerance)
        // Converting there and back returns the original amount.
        for record in records.prefix(50) {
            let there = rates.convert(record.amount, from: record.currency, to: "EUR")!
            let back = rates.convert(there, from: "EUR", to: record.currency)!
            #expect(abs(back - record.amount) < tolerance)
        }
    }

    @Test("Backups round-trip every field exactly")
    func backupRoundTrip() throws {
        var rng = SplitMix64(state: 99)
        let records = (0..<200).map { _ in randomRecord(&rng) }
        let data = try JSONEncoder().encode(Backup(subscriptions: records))
        let decoded = try JSONDecoder().decode(Backup.self, from: data).subscriptions
        #expect(decoded == records)
    }

    @Test("Money parsing accepts exactly what it should")
    func moneyParsing() {
        var rng = SplitMix64(state: 5)
        let us = Locale(identifier: "en_US"), fr = Locale(identifier: "fr_FR")
        for _ in 0..<500 {
            let cents = Int.random(in: 0...99_999_999, using: &rng)
            let text = "\(cents / 100).\(String(format: "%02d", cents % 100))"
            #expect(Money.parse(text, locale: us) == Decimal(cents) / 100)
            #expect(Money.parse(text.replacingOccurrences(of: ".", with: ","), locale: fr) == Decimal(cents) / 100)
        }
        for bad in ["", " ", ".", "1.", ".5", "1,000.00", "1.2.3", "-1", "1e3", "12 CAD", "$5", "１２"] {
            #expect(Money.parse(bad, locale: us) == nil, "Should reject \(bad)")
        }
    }
}
