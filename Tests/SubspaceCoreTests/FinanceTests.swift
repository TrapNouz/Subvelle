import XCTest
@testable import SubspaceCore

final class FinanceTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
    func testMonthEndDoesNotDriftAfterFebruary() throws {
        let start = try date(2024, 1, 31)
        let record = SubscriptionRecord(name: "Monthly", amount: 20, startDate: start, nextRenewal: start)
        let engine = RecurrenceEngine(calendar: calendar)
        XCTAssertEqual(engine.occurrence(record, index: 1), try date(2024, 2, 29))
        XCTAssertEqual(engine.occurrence(record, index: 2), try date(2024, 3, 31))
        XCTAssertEqual(engine.occurrence(record, index: 13), try date(2025, 2, 28))
    }
    func testSameDayEndDateIsValidRegardlessOfTime() throws {
        let day = Calendar.current.startOfDay(for: .now)
        let afternoon = try XCTUnwrap(Calendar.current.date(byAdding: .hour, value: 15, to: day))
        let morning = try XCTUnwrap(Calendar.current.date(byAdding: .hour, value: 9, to: day))
        let record = SubscriptionRecord(name: "One-off", amount: 5, startDate: afternoon, nextRenewal: afternoon, endDate: morning)
        XCTAssertNoThrow(try record.validate())
        var earlier = record
        earlier.endDate = Calendar.current.date(byAdding: .day, value: -1, to: morning)
        XCTAssertThrowsError(try earlier.validate())
    }
    func testLeapYearAnnualAnchorRecovers() throws {
        let start = try date(2024, 2, 29)
        let record = SubscriptionRecord(name: "Annual", amount: 120, interval: .annual, startDate: start, nextRenewal: start)
        let engine = RecurrenceEngine(calendar: calendar)
        XCTAssertEqual(engine.occurrence(record, index: 1), try date(2025, 2, 28))
        XCTAssertEqual(engine.occurrence(record, index: 4), try date(2028, 2, 29))
    }
    func testCustomBiweeklyAndEndDate() throws {
        let start = try date(2025, 1, 1)
        var record = SubscriptionRecord(name: "Custom", amount: 30, interval: .biweekly, startDate: start, nextRenewal: start, endDate: try date(2025, 1, 15))
        let range = DateInterval(start: start, end: try date(2025, 2, 1))
        let engine = RecurrenceEngine(calendar: calendar)
        XCTAssertEqual(engine.payments(record, in: range).map(\.date), [start, try date(2025, 1, 15)])
        record.interval = BillingInterval(count: 3, unit: .day)
        XCTAssertEqual(engine.payments(record, in: range).count, 5)
    }
    func testAnnualAverageIsNotActualPaymentTotal() throws {
        let start = try date(2025, 6, 10)
        let record = SubscriptionRecord(name: "Annual", amount: 120, interval: .annual, startDate: start, nextRenewal: start)
        let summary = FinancialSummary(records: [record], reportingCurrency: "CAD", rates: ExchangeRates(rates: [:]), now: start)
        XCTAssertEqual(summary.monthly, 10)
        XCTAssertEqual(summary.annual, 120)
        let engine = RecurrenceEngine(calendar: calendar)
        XCTAssertTrue(engine.payments(record, in: DateInterval(start: try date(2025, 7, 1), end: try date(2025, 8, 1))).isEmpty)
        XCTAssertEqual(engine.payments(record, in: DateInterval(start: try date(2025, 6, 1), end: try date(2025, 7, 1))).count, 1)
    }
    func testCurrencyCrossRatesAndMissingRates() {
        let rates = ExchangeRates(rates: ["CAD": Decimal(135) / 100, "EUR": Decimal(9) / 10])
        XCTAssertEqual(rates.convert(100, from: "USD", to: "CAD"), 135)
        XCTAssertEqual(rates.convert(90, from: "EUR", to: "CAD"), 135)
        XCTAssertEqual(rates.convert(90, from: "EUR", to: "EUR"), 90)
        XCTAssertNil(rates.convert(10, from: "XYZ", to: "CAD"))
        let summary = FinancialSummary(records: [SubscriptionRecord(name: "USD", amount: 10, currency: "USD"), SubscriptionRecord(name: "JPY", amount: 1000, currency: "JPY")], reportingCurrency: "CAD", rates: rates)
        XCTAssertEqual(summary.monthly, Decimal(135) / 10)
        XCTAssertEqual(summary.missingCurrencies, ["JPY"])
    }
    func testPausedCanceledArchivedAndExpiredAreExcluded() throws {
        let start = try date(2024, 1, 1)
        let records = [SubscriptionRecord(name: "Paused", amount: 10, status: .paused), SubscriptionRecord(name: "Canceled", amount: 10, status: .canceled), SubscriptionRecord(name: "Archived", amount: 10, archived: true), SubscriptionRecord(name: "Expired", amount: 10, startDate: start, nextRenewal: start, endDate: try date(2024, 12, 31))]
        let summary = FinancialSummary(records: records, reportingCurrency: "CAD", rates: ExchangeRates(rates: [:]), now: try date(2025, 1, 1))
        XCTAssertEqual(summary.activeCount, 0)
        XCTAssertEqual(summary.annual, 0)
    }
    func testOldAnchorFindsNextPaymentAndRangeIsHalfOpen() throws {
        let start = try date(2000, 1, 31)
        let record = SubscriptionRecord(name: "Long running", amount: 10, startDate: start, nextRenewal: start)
        let engine = RecurrenceEngine(calendar: calendar)
        XCTAssertEqual(engine.nextPayment(record, from: try date(2025, 2, 1))?.date, try date(2025, 2, 28))
        let payments = engine.payments(record, in: DateInterval(start: try date(2025, 1, 31), end: try date(2025, 3, 31)))
        XCTAssertEqual(payments.count, 2)
    }
    func testDecimalPrecisionAndLargeAmounts() {
        let amount = Decimal(1_000_000_000_000)
        let record = SubscriptionRecord(name: "Large", amount: amount)
        XCTAssertNoThrow(try record.validate())
        let summary = FinancialSummary(records: [record], reportingCurrency: "CAD", rates: ExchangeRates(rates: [:]))
        XCTAssertEqual(summary.monthly, amount)
        XCTAssertEqual(summary.annual, amount * 12)
        XCTAssertEqual(ExchangeRates(rates: ["CAD": Decimal(135) / 100]).convert(Decimal(10) / 100, from: "USD", to: "CAD"), Decimal(135) / 1000)
    }
    func testBackupRoundTripAndValidation() throws {
        let records = [SubscriptionRecord(name: "Private", amount: Decimal(1999) / 100, notes: "Local notes")]
        let encoded = try JSONEncoder().encode(Backup(subscriptions: records))
        let decoded = try JSONDecoder().decode(Backup.self, from: encoded)
        XCTAssertEqual(try decoded.validated(), records)
        XCTAssertThrowsError(try Backup(subscriptions: records + records).validated())
        var future = decoded; future.schemaVersion = 2
        XCTAssertThrowsError(try future.validated())
        var invalid = records[0]; invalid.interval.count = 0
        XCTAssertThrowsError(try invalid.validate())
    }
    func testStrictLocalizedDecimalInput() {
        XCTAssertEqual(Money.parse("19.99", locale: Locale(identifier: "en_CA")), Decimal(1999) / 100)
        XCTAssertEqual(Money.parse("19,99", locale: Locale(identifier: "de_DE")), Decimal(1999) / 100)
        XCTAssertNil(Money.parse("19.99junk"))
        XCTAssertNil(Money.parse("1.2.3"))
        XCTAssertNil(Money.parse("NaN"))
    }
    func testTrialExcludesUnpaidOccurrences() throws {
        let start = try date(2025, 1, 1)
        let firstCharge = try date(2025, 3, 1)
        let record = SubscriptionRecord(name: "Trial", amount: 10, startDate: start, nextRenewal: firstCharge, trialEnd: firstCharge)
        let engine = RecurrenceEngine(calendar: calendar)
        XCTAssertEqual(engine.payments(record, in: DateInterval(start: start, end: try date(2025, 4, 1))).map(\.date), [firstCharge])
        XCTAssertEqual(engine.nextPayment(record, from: start)?.date, firstCharge)
    }
    func testPresetsHaveUniqueNamesAndNoPrices() {
        XCTAssertGreaterThanOrEqual(ServicePreset.all.count, 100)
        XCTAssertEqual(Set(ServicePreset.all.map(\.name)).count, ServicePreset.all.count)
        XCTAssertTrue(Category.allCases.allSatisfy { category in ServicePreset.all.contains { $0.category == category } })
    }
}
