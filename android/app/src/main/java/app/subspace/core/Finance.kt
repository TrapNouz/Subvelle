package app.subspace.core

import androidx.compose.runtime.Immutable
import kotlinx.serialization.Serializable
import java.math.BigDecimal
import java.math.MathContext
import java.text.DecimalFormatSymbols
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Currency
import java.util.Locale

@Immutable
data class Payment(val subscription: SubscriptionRecord, val date: LocalDate) {
    val id: String get() = "${subscription.id}-$date"
}

/** Occurrences are always calculated from the original anchor, never from a clamped previous date. */
class RecurrenceEngine(private val zone: ZoneId = ZoneId.systemDefault()) {
    fun occurrence(record: SubscriptionRecord, index: Long): LocalDate? {
        val interval = record.interval
        if (interval.count !in 1..1000 || kotlin.math.abs(index) >= 1_000_000) return null
        val anchor = record.renewalDay(zone)
        val value = interval.count * index
        return try {
            when (interval.unit) {
                BillingUnit.DAY -> anchor.plusDays(value)
                BillingUnit.WEEK -> anchor.plusDays(value * 7)
                BillingUnit.MONTH, BillingUnit.YEAR -> {
                    val months = value * if (interval.unit == BillingUnit.YEAR) 12 else 1
                    val target = anchor.withDayOfMonth(1).plusMonths(months)
                    target.withDayOfMonth(minOf(anchor.dayOfMonth, target.lengthOfMonth()))
                }
            }
        } catch (_: java.time.DateTimeException) { null } catch (_: ArithmeticException) { null }
    }
    private fun estimatedIndex(record: SubscriptionRecord, date: LocalDate): Long {
        val anchor = record.renewalDay(zone)
        val count = record.interval.count.toLong().takeIf { it > 0 } ?: return 0
        return when (record.interval.unit) {
            BillingUnit.DAY -> ChronoUnit.DAYS.between(anchor, date) / count
            BillingUnit.WEEK -> ChronoUnit.DAYS.between(anchor, date) / (7 * count)
            BillingUnit.MONTH -> ChronoUnit.MONTHS.between(anchor, date) / count
            BillingUnit.YEAR -> ChronoUnit.YEARS.between(anchor, date) / count
        }
    }
    private fun lowerBound(record: SubscriptionRecord, from: LocalDate): LocalDate =
        listOfNotNull(from, record.startDay(zone), record.trialEndDay(zone)).max()

    /** Scheduled payments in [start, endExclusive). */
    fun payments(record: SubscriptionRecord, start: LocalDate, endExclusive: LocalDate): List<Payment> {
        if (record.status != SubscriptionStatus.ACTIVE || record.archived || record.interval.count <= 0) return emptyList()
        val lower = lowerBound(record, start)
        val upper = record.endDay(zone)?.plusDays(1)?.let { minOf(it, endExclusive) } ?: endExclusive
        if (lower >= upper) return emptyList()
        var index = estimatedIndex(record, lower) - 2
        val result = ArrayList<Payment>()
        // A bounded loop keeps corrupt data from creating an unbounded loop.
        repeat(40_000) {
            val date = occurrence(record, index) ?: return result
            if (date >= upper) return result
            if (date >= lower) result.add(Payment(record, date))
            index++
        }
        return result
    }
    fun nextPayment(record: SubscriptionRecord, from: LocalDate = LocalDate.now(zone)): Payment? {
        if (record.status != SubscriptionStatus.ACTIVE || record.archived) return null
        val lower = lowerBound(record, from)
        val initial = estimatedIndex(record, lower) - 2
        for (index in initial until initial + 8) {
            val date = occurrence(record, index) ?: continue
            if (date >= lower) {
                val end = record.endDay(zone)
                return if (end != null && date > end) null else Payment(record, date)
            }
        }
        return null
    }
}

@Immutable
@Serializable
data class ExchangeRates(
    val base: String = "USD",
    val rates: Map<String, @Serializable(with = DecimalSerializer::class) BigDecimal> = emptyMap(),
    /** Epoch milliseconds of the publication day (local midnight). */
    val updatedAt: Long = 0,
) {
    fun convert(amount: BigDecimal, from: String, to: String): BigDecimal? {
        if (from == to) return amount
        val source = if (from == base) BigDecimal.ONE else rates[from]
        val target = if (to == base) BigDecimal.ONE else rates[to]
        if (source == null || target == null || source.signum() <= 0 || target.signum() <= 0) return null
        return amount.divide(source, Money.MATH).multiply(target, Money.MATH)
    }
    val hasRates: Boolean get() = updatedAt > 0
    fun isStale(now: Instant = Instant.now()): Boolean = now.toEpochMilli() - updatedAt > 4L * 86_400_000
}

@Immutable
data class FinancialSummary(
    val monthly: BigDecimal, val annual: BigDecimal, val weekly: BigDecimal,
    val activeCount: Int, val missingCurrencies: Set<String>,
) {
    companion object {
        fun of(records: List<SubscriptionRecord>, reportingCurrency: String, rates: ExchangeRates, today: LocalDate = LocalDate.now()): FinancialSummary {
            var annual = BigDecimal.ZERO
            var active = 0
            val missing = mutableSetOf<String>()
            for (record in records) {
                if (!record.isCurrentlyActive(today)) continue
                active++
                val converted = rates.convert(record.amount, record.currency, reportingCurrency)
                if (converted == null) { missing += record.currency; continue }
                annual = annual.add(converted.multiply(record.interval.periodsPerYear, Money.MATH))
            }
            return FinancialSummary(
                monthly = annual.divide(BigDecimal(12), Money.MATH),
                annual = annual,
                weekly = annual.multiply(BigDecimal(7)).divide(BillingInterval.MEAN_YEAR, Money.MATH),
                activeCount = active, missingCurrencies = missing,
            )
        }
    }
}

fun SubscriptionRecord.isCurrentlyActive(today: LocalDate = LocalDate.now()): Boolean =
    status == SubscriptionStatus.ACTIVE && !archived && (endDay()?.let { it >= today } ?: true)

object Money {
    val MATH: MathContext = MathContext.DECIMAL128

    /** Strictly accepts localized decimal input, with no grouping or trailing text. */
    fun parse(text: String, locale: Locale = Locale.getDefault()): BigDecimal? {
        val separator = DecimalFormatSymbols.getInstance(locale).decimalSeparator.toString()
        val normalized = text.trim().replace(separator, ".")
        if (normalized.length > 38 || !Regex("^[0-9]+(?:\\.[0-9]+)?$").matches(normalized)) return null
        return normalized.toBigDecimalOrNull()
    }
    /** Formatters are expensive to create, so each thread keeps one per locale and currency. */
    private val formatters = ThreadLocal.withInitial { HashMap<String, NumberFormat>() }

    fun format(amount: BigDecimal, currency: String, locale: Locale = Locale.getDefault()): String = try {
        formatters.get()!!.getOrPut("${locale.toLanguageTag()}|$currency") {
            NumberFormat.getCurrencyInstance(locale).apply { this.currency = Currency.getInstance(currency) }
        }.format(amount)
    } catch (_: IllegalArgumentException) { "${amount.toPlainString()} $currency" }

    /** Editing text for an amount, in the user's decimal style. */
    fun editingText(amount: BigDecimal, locale: Locale = Locale.getDefault()): String =
        amount.stripTrailingZeros().toPlainString().replace(".", DecimalFormatSymbols.getInstance(locale).decimalSeparator.toString())
}

object Currencies {
    val common = listOf("CAD", "USD", "EUR", "GBP", "AUD", "JPY", "CHF", "NZD", "CNY", "INR", "KRW", "BRL", "MXN", "SGD", "HKD", "SEK", "NOK", "DKK", "PLN", "CZK", "ZAR")
    /** Circulating ISO 4217 codes (funds, metals and testing codes excluded). */
    val codes: Set<String> by lazy {
        val excluded = setOf("XAU", "XAG", "XPT", "XPD", "XTS", "XXX", "XBA", "XBB", "XBC", "XBD", "XDR", "XSU", "XUA", "BOV", "CHE", "CHW", "CLF", "COU", "MXV", "USN", "USS", "UYI", "UYW")
        Currency.getAvailableCurrencies().map { it.currencyCode }.filter { it.length == 3 && it !in excluded }.toSortedSet()
    }
    val others: List<String> by lazy { codes.filter { it !in common } }
    fun name(code: String, locale: Locale = Locale.getDefault()): String =
        runCatching { Currency.getInstance(code).getDisplayName(locale) }.getOrDefault(code)
}
