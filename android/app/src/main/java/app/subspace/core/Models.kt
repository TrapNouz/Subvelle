package app.subspace.core

import androidx.compose.runtime.Immutable
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonUnquotedLiteral
import kotlinx.serialization.json.jsonPrimitive
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

// The JSON format matches the iOS app's Swift `Codable` output exactly, so backups move between
// iPhone and Android: Swift encodes `Date` as seconds since 2001-01-01, `Decimal` as a JSON number,
// `UUID` as an uppercase string, enums by raw value, and omits nil optionals.

/** Swift `Decimal` <-> exact JSON number, never through binary floating point. */
object DecimalSerializer : KSerializer<BigDecimal> {
    override val descriptor = PrimitiveSerialDescriptor("Decimal", PrimitiveKind.STRING)
    @OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
    override fun serialize(encoder: Encoder, value: BigDecimal) {
        val text = value.stripTrailingZeros().toPlainString()
        if (encoder is JsonEncoder) encoder.encodeJsonElement(JsonUnquotedLiteral(text)) else encoder.encodeString(text)
    }
    override fun deserialize(decoder: Decoder): BigDecimal =
        if (decoder is JsonDecoder) BigDecimal(decoder.decodeJsonElement().jsonPrimitive.content) else BigDecimal(decoder.decodeString())
}

/** Swift `Date` default encoding: seconds (with fraction) since 2001-01-01T00:00:00Z. */
object AppleDateSerializer : KSerializer<Instant> {
    private const val REFERENCE_EPOCH_SECONDS = 978_307_200L
    override val descriptor = PrimitiveSerialDescriptor("AppleDate", PrimitiveKind.DOUBLE)
    override fun serialize(encoder: Encoder, value: Instant) {
        val seconds = BigDecimal.valueOf(value.epochSecond - REFERENCE_EPOCH_SECONDS).add(BigDecimal.valueOf(value.nano.toLong(), 9))
        if (encoder is JsonEncoder) encoder.encodeJsonElement(JsonPrimitive(seconds.toDouble())) else encoder.encodeDouble(seconds.toDouble())
    }
    override fun deserialize(decoder: Decoder): Instant {
        val seconds = if (decoder is JsonDecoder) BigDecimal(decoder.decodeJsonElement().jsonPrimitive.content) else BigDecimal.valueOf(decoder.decodeDouble())
        val whole = seconds.toBigInteger().toLong()
        val nanos = seconds.subtract(BigDecimal.valueOf(whole)).movePointRight(9).toLong()
        return Instant.ofEpochSecond(REFERENCE_EPOCH_SECONDS + whole, nanos)
    }
}

@Serializable enum class BillingUnit { @SerialName("day") DAY, @SerialName("week") WEEK, @SerialName("month") MONTH, @SerialName("year") YEAR;
    val label: String get() = name.lowercase()
}

@Immutable
@Serializable
data class BillingInterval(val count: Int, val unit: BillingUnit) {
    val label: String get() = when (this) {
        WEEKLY -> "Weekly"; BIWEEKLY -> "Every two weeks"; MONTHLY -> "Monthly"
        QUARTERLY -> "Every three months"; SEMIANNUAL -> "Every six months"; ANNUAL -> "Annually"
        else -> "Every $count ${unit.label}${if (count == 1) "" else "s"}"
    }
    /** Fixed day/week plans use the Gregorian mean year (365.2425 days); month/year plans use 12 months. */
    val periodsPerYear: BigDecimal get() {
        if (count <= 0) return BigDecimal.ZERO
        return when (unit) {
            BillingUnit.DAY -> MEAN_YEAR.divide(BigDecimal(count), Money.MATH)
            BillingUnit.WEEK -> MEAN_YEAR.divide(BigDecimal(7 * count), Money.MATH)
            BillingUnit.MONTH -> BigDecimal(12).divide(BigDecimal(count), Money.MATH)
            BillingUnit.YEAR -> BigDecimal.ONE.divide(BigDecimal(count), Money.MATH)
        }
    }
    companion object {
        val MEAN_YEAR = BigDecimal("365.2425")
        val WEEKLY = BillingInterval(1, BillingUnit.WEEK)
        val BIWEEKLY = BillingInterval(2, BillingUnit.WEEK)
        val MONTHLY = BillingInterval(1, BillingUnit.MONTH)
        val QUARTERLY = BillingInterval(3, BillingUnit.MONTH)
        val SEMIANNUAL = BillingInterval(6, BillingUnit.MONTH)
        val ANNUAL = BillingInterval(1, BillingUnit.YEAR)
        val STANDARD = listOf(WEEKLY, BIWEEKLY, MONTHLY, QUARTERLY, SEMIANNUAL, ANNUAL)
    }
}

@Serializable enum class SubscriptionStatus { @SerialName("active") ACTIVE, @SerialName("paused") PAUSED, @SerialName("canceled") CANCELED;
    val label: String get() = name.lowercase().replaceFirstChar { it.uppercase() }
}

@Serializable enum class Category(val label: String) {
    @SerialName("Streaming") STREAMING("Streaming"), @SerialName("Music") MUSIC("Music"), @SerialName("AI") AI("AI"),
    @SerialName("Gaming") GAMING("Gaming"), @SerialName("Privacy & VPN") PRIVACY("Privacy & VPN"),
    @SerialName("Productivity") PRODUCTIVITY("Productivity"), @SerialName("Cloud") CLOUD("Cloud"),
    @SerialName("Fitness") FITNESS("Fitness"), @SerialName("Education") EDUCATION("Education"), @SerialName("News") NEWS("News"),
    @SerialName("Hosting") HOSTING("Hosting"), @SerialName("Developer") DEVELOPER("Developer"), @SerialName("Other") OTHER("Other");
}

class DataException(message: String) : Exception(message)

/**
 * One subscription. Instants keep the exact values written by iOS; schedule logic works on local
 * calendar days through the `*Day` helpers, exactly like the Swift app's `startOfDay` comparisons.
 */
@Immutable
@Serializable
data class SubscriptionRecord(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val name: String = "",
    val symbol: String = "creditcard.fill",
    @Serializable(with = DecimalSerializer::class) val amount: BigDecimal = BigDecimal.ZERO,
    val currency: String = "CAD",
    val interval: BillingInterval = BillingInterval.MONTHLY,
    @Serializable(with = AppleDateSerializer::class) val startDate: Instant = Instant.now(),
    @Serializable(with = AppleDateSerializer::class) val nextRenewal: Instant = Instant.now(),
    val category: Category = Category.OTHER,
    val notes: String = "",
    @Serializable(with = AppleDateSerializer::class) val trialEnd: Instant? = null,
    val status: SubscriptionStatus = SubscriptionStatus.ACTIVE,
    @Serializable(with = AppleDateSerializer::class) val endDate: Instant? = null,
    // Must default to null: iOS omits the key when reminders are off. New records set it explicitly.
    val reminderDays: Int? = null,
    val archived: Boolean = false,
) {
    fun startDay(zone: ZoneId = ZoneId.systemDefault()): LocalDate = startDate.atZone(zone).toLocalDate()
    fun renewalDay(zone: ZoneId = ZoneId.systemDefault()): LocalDate = nextRenewal.atZone(zone).toLocalDate()
    fun trialEndDay(zone: ZoneId = ZoneId.systemDefault()): LocalDate? = trialEnd?.atZone(zone)?.toLocalDate()
    fun endDay(zone: ZoneId = ZoneId.systemDefault()): LocalDate? = endDate?.atZone(zone)?.toLocalDate()

    /** Same rules and messages as the iOS app's `SubscriptionRecord.validate()`. */
    fun validate(zone: ZoneId = ZoneId.systemDefault()) {
        if (name.isBlank() || name.length > 120) throw DataException("Enter a service name of 1–120 characters.")
        if (amount.signum() <= 0 || amount > BigDecimal("1000000000000")) throw DataException("Enter an amount greater than zero and no more than one trillion.")
        if (currency.length != 3 || currency !in Currencies.codes) throw DataException("Choose a valid ISO currency.")
        if (interval.count !in 1..1000) throw DataException("Billing intervals must be between 1 and 1,000.")
        val start = startDay(zone)
        if (renewalDay(zone) < start || (endDay(zone)?.let { it < start } == true)) throw DataException("Renewal and end dates must be on or after the start date.")
        trialEndDay(zone)?.let { if (it < start || it > renewalDay(zone)) throw DataException("Trial end must be between the start date and the first paid renewal.") }
        if (reminderDays != null && reminderDays !in listOf(1, 3, 7, 14)) throw DataException("Unsupported reminder interval.")
    }
}

/** Same layout as the iOS `Backup` file. */
@Serializable
data class Backup(
    val schemaVersion: Int = 1,
    @Serializable(with = AppleDateSerializer::class) val exportedAt: Instant = Instant.now(),
    val subscriptions: List<SubscriptionRecord>,
) {
    fun validated(): List<SubscriptionRecord> {
        if (schemaVersion != 1) throw DataException("This backup version is not supported. Update Subvelle before importing.")
        if (subscriptions.size > 10_000 || subscriptions.map { it.id }.toSet().size != subscriptions.size) throw DataException("Backup contains too many records or duplicate IDs.")
        subscriptions.forEach { it.validate() }
        return subscriptions
    }
}

/** Shared JSON configuration: tolerant of unknown keys from newer iOS versions, omits nulls like Swift. */
@OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
val AppJson = kotlinx.serialization.json.Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    encodeDefaults = true
}
