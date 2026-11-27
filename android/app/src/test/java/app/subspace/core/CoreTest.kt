package app.subspace.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigDecimal
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.Locale

/** Ports of the iOS `FinanceTests` and `SubscriptionListQueryTests`, plus cross-platform backup checks. */
class CoreTest {
    private val utc: ZoneOffset = ZoneOffset.UTC
    private fun day(y: Int, m: Int, d: Int) = LocalDate.of(y, m, d)
    private fun instant(y: Int, m: Int, d: Int) = day(y, m, d).atStartOfDay(utc).toInstant()
    private fun record(name: String, amount: String, interval: BillingInterval = BillingInterval.MONTHLY, start: LocalDate = day(2024, 1, 1), renewal: LocalDate = start, currency: String = "CAD", end: LocalDate? = null, status: SubscriptionStatus = SubscriptionStatus.ACTIVE, archived: Boolean = false, notes: String = "", category: Category = Category.OTHER) =
        SubscriptionRecord(name = name, amount = BigDecimal(amount), interval = interval, startDate = start.atStartOfDay(utc).toInstant(), nextRenewal = renewal.atStartOfDay(utc).toInstant(), currency = currency, endDate = end?.atStartOfDay(utc)?.toInstant(), status = status, archived = archived, notes = notes, category = category)

    @Test fun monthEndDoesNotDriftAfterFebruary() {
        val engine = RecurrenceEngine(utc)
        val r = record("Monthly", "20", start = day(2024, 1, 31))
        assertEquals(day(2024, 2, 29), engine.occurrence(r, 1))
        assertEquals(day(2024, 3, 31), engine.occurrence(r, 2))
        assertEquals(day(2025, 2, 28), engine.occurrence(r, 13))
    }

    @Test fun leapYearAnnualAnchorRecovers() {
        val engine = RecurrenceEngine(utc)
        val r = record("Annual", "120", BillingInterval.ANNUAL, start = day(2024, 2, 29))
        assertEquals(day(2025, 2, 28), engine.occurrence(r, 1))
        assertEquals(day(2028, 2, 29), engine.occurrence(r, 4))
    }

    @Test fun customBiweeklyAndInclusiveEndDate() {
        val engine = RecurrenceEngine(utc)
        val r = record("Custom", "30", BillingInterval.BIWEEKLY, start = day(2025, 1, 1), end = day(2025, 1, 15))
        val dates = engine.payments(r, day(2025, 1, 1), day(2025, 3, 1)).map { it.date }
        assertEquals(listOf(day(2025, 1, 1), day(2025, 1, 15)), dates)
        assertNull(engine.nextPayment(r, day(2025, 1, 16)))
    }

    @Test fun trialEndBoundsFirstPayment() {
        val engine = RecurrenceEngine(utc)
        val r = record("Trial", "10", start = day(2025, 1, 1), renewal = day(2025, 2, 1)).copy(trialEnd = instant(2025, 2, 1))
        assertEquals(day(2025, 2, 1), engine.nextPayment(r, day(2025, 1, 5))?.date)
        assertEquals(listOf(day(2025, 2, 1), day(2025, 3, 1)), engine.payments(r, day(2024, 12, 1), day(2025, 3, 2)).map { it.date })
    }

    @Test fun nextPaymentLooksForwardFromAnchorInThePast() {
        val engine = RecurrenceEngine(utc)
        val weekly = record("Weekly", "5", BillingInterval.WEEKLY, start = day(2025, 1, 6))
        assertEquals(day(2025, 3, 3), engine.nextPayment(weekly, day(2025, 2, 25))?.date)
        val tenDays = record("Ten", "5", BillingInterval(10, BillingUnit.DAY), start = day(2025, 1, 1))
        assertEquals(day(2025, 1, 31), engine.nextPayment(tenDays, day(2025, 1, 22))?.date)
    }

    @Test fun summaryNormalizesAndConvertsBeforeSumming() {
        val rates = ExchangeRates(rates = mapOf("CAD" to BigDecimal("1.35"), "EUR" to BigDecimal("0.9")), updatedAt = 1)
        val records = listOf(
            record("Annual", "120", BillingInterval.ANNUAL, currency = "CAD"),
            record("USD monthly", "10", currency = "USD"),
            record("Paused", "10", status = SubscriptionStatus.PAUSED),
            record("Archived", "10", archived = true),
            record("Expired", "10", end = day(2024, 12, 31)),
            record("Unknown", "10", currency = "XCD"),
        )
        val summary = FinancialSummary.of(records, "CAD", rates, today = day(2025, 6, 1))
        assertEquals(0, BigDecimal("282").compareTo(summary.annual.setScale(10, java.math.RoundingMode.HALF_EVEN)))
        assertEquals(0, BigDecimal("23.5").compareTo(summary.monthly.setScale(10, java.math.RoundingMode.HALF_EVEN)))
        assertEquals(3, summary.activeCount)
        assertEquals(setOf("XCD"), summary.missingCurrencies)
    }

    @Test fun periodsPerYear() {
        assertEquals(0, BigDecimal("52.1775").compareTo(BillingInterval.WEEKLY.periodsPerYear.setScale(4, java.math.RoundingMode.HALF_EVEN)))
        assertEquals(0, BigDecimal("4").compareTo(BillingInterval.QUARTERLY.periodsPerYear))
    }

    @Test fun moneyParsingIsStrictAndLocalized() {
        assertEquals(BigDecimal("12.99"), Money.parse("12.99", Locale.US))
        assertEquals(BigDecimal("12.99"), Money.parse(" 12,99 ", Locale.FRANCE))
        assertNull(Money.parse("1,000.00", Locale.US))
        assertNull(Money.parse("12.99 CAD", Locale.US))
        assertNull(Money.parse("-5", Locale.US))
        assertEquals("12,5", Money.editingText(BigDecimal("12.50"), Locale.FRANCE))
    }

    @Test fun validationMatchesIos() {
        val ok = record("Ok", "5", start = day(2025, 1, 1))
        ok.validate(utc)
        // Same-day end date is valid regardless of time of day (fixed on iOS in v1.0.1).
        ok.copy(endDate = day(2025, 1, 1).atTime(9, 0).toInstant(utc), startDate = day(2025, 1, 1).atTime(15, 0).toInstant(utc)).validate(utc)
        assertThrows(DataException::class.java) { ok.copy(name = " ").validate(utc) }
        assertThrows(DataException::class.java) { ok.copy(amount = BigDecimal.ZERO).validate(utc) }
        assertThrows(DataException::class.java) { ok.copy(currency = "ABC").validate(utc) }
        assertThrows(DataException::class.java) { ok.copy(endDate = instant(2024, 12, 31)).validate(utc) }
        assertThrows(DataException::class.java) { ok.copy(reminderDays = 5).validate(utc) }
        assertThrows(DataException::class.java) { ok.copy(trialEnd = instant(2025, 3, 1)).validate(utc) }
    }

    @Test fun listQueryFiltersSearchesAndSorts() {
        val rates = ExchangeRates(rates = mapOf("CAD" to BigDecimal("1.35")), updatedAt = 1)
        val records = listOf(
            record("beta", "5", notes = "shared with Sam", category = Category.MUSIC),
            record("Alpha", "20", category = Category.MUSIC),
            record("Gamma", "1", archived = true),
            record("Delta", "10", status = SubscriptionStatus.PAUSED),
        )
        val today = day(2025, 1, 15)
        assertEquals(listOf("beta"), SubscriptionListQuery(search = "SAM").apply(records, "CAD", rates, today, utc).map { it.name })
        assertEquals(listOf("Alpha", "beta", "Delta"), SubscriptionListQuery(sort = SubscriptionSort.NAME).apply(records, "CAD", rates, today, utc).map { it.name })
        assertEquals(listOf("Alpha", "Delta", "beta"), SubscriptionListQuery(sort = SubscriptionSort.AMOUNT).apply(records, "CAD", rates, today, utc).map { it.name })
        assertEquals(listOf("Gamma"), SubscriptionListQuery(scope = SubscriptionScope.ARCHIVED).apply(records, "CAD", rates, today, utc).map { it.name })
        assertEquals(listOf("Delta"), SubscriptionListQuery(scope = SubscriptionScope.PAUSED).apply(records, "CAD", rates, today, utc).map { it.name })
        assertEquals(2, SubscriptionListQuery(category = Category.MUSIC).apply(records, "CAD", rates, today, utc).size)
    }

    @Test fun presetsMatchIos() {
        assertEquals(192, ServicePreset.all.size)
        assertEquals(ServicePreset.all.size, ServicePreset.all.map { it.name }.toSet().size)
        val missing = ServicePreset.all.filter { app.subspace.ui.BrandCatalog.brand(it.name) == null }.map { it.name }
        assertTrue("No brand for $missing", missing.isEmpty())
        assertTrue(ServicePreset.all.count { app.subspace.ui.BrandCatalog.brand(it.name)?.logo != null } >= 120)
        assertEquals("YP", ServicePreset.all.first { it.name == "YouTube Premium" }.initials)
    }

    @Test fun updateVersionComparisonMatchesIos() {
        assertEquals("1.2.0", AppVersion.normalized("v1.2.0"))
        assertTrue(AppVersion.isNewer("v1.3.0", "1.2.0"))
        assertTrue(AppVersion.isNewer("1.10.0", "1.9.9"))
        assertFalse(AppVersion.isNewer("v1.2.0", "1.2.0"))
        assertFalse(AppVersion.isNewer("1.2", "1.2.0"))
        assertFalse(AppVersion.isNewer("1.1.3", "1.2.0"))
        assertFalse(AppVersion.isNewer("1.2.0-beta", "1.2.0"))
    }

    @Test fun currenciesAreOnlyOnesIphoneAccepts() {
        assertEquals(157, Currencies.codes.size)
        listOf("DEM", "FRF", "ITL", "ESP", "VEB", "ZWD", "XAU", "XXX").forEach { assertFalse("$it must not be offered", it in Currencies.codes) }
        (Currencies.common + Currencies.codes).forEach { java.util.Currency.getInstance(it) }  // all known to Java for names
        assertTrue(Currencies.codes.containsAll(Currencies.common))
    }

    @Test fun brandMatchingMatchesIos() {
        val catalog = app.subspace.ui.BrandCatalog
        assertEquals(app.subspace.R.drawable.brand_netflix, catalog.brand("Netflix")?.logo)
        assertEquals(app.subspace.R.drawable.brand_claude, catalog.brand("claude pro")?.logo)
        assertEquals(app.subspace.R.drawable.brand_spotify, catalog.brand("Spotify Family")?.logo)
        assertEquals(0xFF113CCFL, catalog.brand("Disney Plus")?.argb)
        assertEquals(catalog.brand("Vidéotron"), catalog.brand("Videotron"))
        assertNull(catalog.brand("Plan 01")); assertNull(catalog.brand(""))
        // Whole words only: lookalike names must not borrow another brand's logo.
        listOf("Applebee's", "Uberti Gym", "Notional", "Calmer Yoga").forEach { assertNull(it, catalog.brand(it)) }
        assertEquals(app.subspace.R.drawable.brand_youtube, catalog.brand("YouTube Premium Family")?.logo)
        assertEquals(app.subspace.R.drawable.brand_netflix, catalog.brand("  Netflix   Standard ")?.logo)
        assertTrue(app.subspace.ui.Brand(null, 0xFFFFFC00L).prefersDarkForeground)
        assertFalse(app.subspace.ui.Brand(null, 0xFFE50914L).prefersDarkForeground)
    }

    @Test fun backupPlanRules() {
        assertEquals("Subvelle Backup 2026-03-07.json", BackupPlan.snapshotName(day(2026, 3, 7)))
        val snapshots = (1..16).map { "Subvelle Backup 2026-01-%02d.json".format(it) }
        assertEquals(listOf("Subvelle Backup 2026-01-01.json", "Subvelle Backup 2026-01-02.json"), BackupPlan.snapshotsToPrune(snapshots.shuffled() + listOf(BackupPlan.LATEST_FILE_NAME, "Notes.txt")))
        assertTrue(BackupPlan.isDue(null)); assertFalse(BackupPlan.isDue(1000, 1000 + 3_600_000))
        assertTrue(BackupPlan.isOverdue(null))
    }

    // ---- Cross-platform: a backup written by the real iOS code (SubspaceCore) must load here, ----
    // ---- and a backup written here must keep the exact iOS field names and value types.       ----

    private fun iosFixture(): String = javaClass.getResource("/ios-backup.json")!!.readText()

    @Test fun readsBackupWrittenByIos() {
        val toronto = ZoneId.of("America/Toronto")
        val backup = AppJson.decodeFromString(Backup.serializer(), iosFixture())
        val records = backup.validated()
        assertEquals(3, records.size)
        val netflix = records[0]
        assertEquals("E621E1F8-C36C-495A-93FC-0C247A3E6E5F", netflix.id)
        assertEquals(BigDecimal("16.49"), netflix.amount)
        assertEquals(day(2024, 1, 31), netflix.startDay(toronto))
        assertEquals(Category.STREAMING, netflix.category)
        assertEquals(3, netflix.reminderDays)
        val proton = records[1]
        assertEquals(Category.PRIVACY, proton.category)
        assertEquals(SubscriptionStatus.PAUSED, proton.status)
        assertTrue(proton.archived)
        assertNull(proton.reminderDays)
        assertEquals(day(2024, 2, 29), proton.trialEndDay(toronto))
        assertEquals(BillingInterval(10, BillingUnit.DAY), records[2].interval)
        assertEquals(BigDecimal("12.5"), records[2].amount)
        // iOS's 2:30 PM local time survives exactly.
        assertEquals(java.time.LocalDateTime.of(2024, 1, 31, 14, 30), netflix.startDate.atZone(toronto).toLocalDateTime())
    }

    @Test fun writesIosCompatibleJsonThatRoundTrips() {
        val original = AppJson.decodeFromString(Backup.serializer(), iosFixture())
        val written = AppJson.encodeToString(Backup.serializer(), original)
        val tree = AppJson.parseToJsonElement(written).toString()
        assertTrue(tree.contains("\"amount\":16.49"))          // number, not string
        assertTrue(tree.contains("\"startDate\":7.284222E8") || tree.contains("\"startDate\":728422200"))
        assertFalse(tree.contains("\"reminderDays\":null"))   // nil omitted, like Swift
        assertTrue(tree.contains("\"category\":\"Privacy & VPN\""))
        assertEquals(original, AppJson.decodeFromString(Backup.serializer(), written))
    }

    /** Writes an Android-made backup to build/ so CI (or a developer) can check it with the iOS code. */
    @Test fun writesBackupForIosVerification() {
        val records = listOf(
            SubscriptionRecord(name = "Android Netflix", amount = BigDecimal("16.49"), currency = "CAD", startDate = instant(2025, 1, 31), nextRenewal = instant(2025, 1, 31), category = Category.STREAMING, reminderDays = 7),
            SubscriptionRecord(name = "Android Proton", amount = BigDecimal("0.10"), currency = "EUR", interval = BillingInterval(3, BillingUnit.WEEK), startDate = instant(2025, 2, 1), nextRenewal = instant(2025, 3, 1), trialEnd = instant(2025, 3, 1), endDate = instant(2027, 1, 1), status = SubscriptionStatus.CANCELED, archived = true, category = Category.PRIVACY),
        )
        val file = java.io.File("build/android-backup.json")
        file.writeText(AppJson.encodeToString(Backup.serializer(), Backup(subscriptions = records)))
        assertEquals(2, AppJson.decodeFromString(Backup.serializer(), file.readText()).validated().size)
    }
}
