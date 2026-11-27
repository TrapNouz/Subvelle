package app.subspace.core

import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.math.BigDecimal
import java.time.LocalDate
import java.time.ZoneId
import java.util.TimeZone

/**
 * The iPhone code (SubspaceCore) generated 400 random subscriptions in a time zone with daylight
 * saving and recorded every payment date, next payment and total it computes
 * (resources/cross-platform-schedules.json). The Android code must reproduce all of them exactly.
 */
class CrossPlatformTest {
    private val fixture = AppJson.parseToJsonElement(javaClass.getResource("/cross-platform-schedules.json")!!.readText()).jsonObject
    private val zone = ZoneId.of(fixture["zone"]!!.jsonPrimitive.content)
    private var previousZone: TimeZone? = null

    // The app runs in the phone's time zone; mirror the zone the iPhone code used.
    @Before fun useFixtureZone() { previousZone = TimeZone.getDefault(); TimeZone.setDefault(TimeZone.getTimeZone(zone)) }
    @After fun restoreZone() { previousZone?.let(TimeZone::setDefault) }

    private val records by lazy { AppJson.decodeFromString(Backup.serializer(), fixture["backup"]!!.jsonPrimitive.content).subscriptions.associateBy { it.id } }
    private fun day(key: String) = LocalDate.parse(fixture[key]!!.jsonPrimitive.content)

    @Test fun everyPaymentDateMatchesIphone() {
        val engine = RecurrenceEngine(zone)
        val mismatches = mutableListOf<String>()
        var compared = 0
        for (expectation in fixture["expectations"]!!.jsonArray) {
            val e = expectation.jsonObject
            val record = records.getValue(e["id"]!!.jsonPrimitive.content)
            val expected = e["payments"]!!.jsonArray.map { it.jsonPrimitive.content }
            val actual = engine.payments(record, day("windowStart"), day("windowEnd")).map { it.date.toString() }
            compared += expected.size
            if (actual != expected) mismatches += "${record.name} ${record.interval} anchor ${record.renewalDay(zone)}: iPhone ${expected.size} vs Android ${actual.size}, first difference ${expected.zip(actual).firstOrNull { it.first != it.second } ?: (expected.size to actual.size)}"
        }
        assertTrue("${mismatches.size} schedules differ:\n" + mismatches.take(10).joinToString("\n"), mismatches.isEmpty())
        assertTrue(compared > 5_000)
    }

    @Test fun nextPaymentMatchesIphone() {
        val engine = RecurrenceEngine(zone)
        val todays = fixture["todays"]!!.jsonArray.map { LocalDate.parse(it.jsonPrimitive.content) }
        val mismatches = mutableListOf<String>()
        for (expectation in fixture["expectations"]!!.jsonArray) {
            val e = expectation.jsonObject
            val record = records.getValue(e["id"]!!.jsonPrimitive.content)
            e["next"]!!.jsonArray.map { it.jsonPrimitive.content }.zip(todays).forEach { (expected, today) ->
                val actual = engine.nextPayment(record, today)?.date?.toString() ?: ""
                if (actual != expected) mismatches += "${record.name} ${record.interval} today $today: iPhone '$expected' vs Android '$actual'"
            }
        }
        assertTrue("${mismatches.size} next payments differ:\n" + mismatches.take(10).joinToString("\n"), mismatches.isEmpty())
    }

    @Test fun totalsMatchIphone() {
        val rates = ExchangeRates(rates = mapOf("CAD" to BigDecimal("1.3712"), "EUR" to BigDecimal("0.9214")), updatedAt = 1)
        val summary = FinancialSummary.of(records.values.toList(), "CAD", rates, day("summaryDay"))
        val tolerance = BigDecimal("0.000000001")
        assertTrue("annual ${summary.annual} vs ${fixture["annualCAD"]}", (summary.annual - BigDecimal(fixture["annualCAD"]!!.jsonPrimitive.content)).abs() < tolerance)
        assertTrue("monthly ${summary.monthly} vs ${fixture["monthlyCAD"]}", (summary.monthly - BigDecimal(fixture["monthlyCAD"]!!.jsonPrimitive.content)).abs() < tolerance)
        assertEquals(fixture["activeCount"]!!.jsonPrimitive.int, summary.activeCount)
        assertEquals(fixture["missing"]!!.jsonArray.map { it.jsonPrimitive.content }.toSet(), summary.missingCurrencies)
    }
}
