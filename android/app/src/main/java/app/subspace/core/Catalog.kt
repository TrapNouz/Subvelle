package app.subspace.core

import androidx.compose.runtime.Immutable
import java.math.BigDecimal
import java.time.LocalDate
import java.time.ZoneId

@Immutable
data class ServicePreset(val name: String, val category: Category) {
    val initials: String get() = name.split(" ").filter { it.isNotEmpty() }.take(2).map { it.first() }.joinToString("")

    companion object {
        /** Same 147 services as the iOS app. Names only: no logos and no assumed prices. */
        val all: List<ServicePreset> by lazy {
            val groups = listOf(
                Category.STREAMING to listOf("Netflix", "Disney+", "YouTube Premium", "Apple TV", "Prime Video", "Hulu", "HBO Max", "Peacock", "Paramount+", "Crunchyroll", "MUBI", "BritBox", "Shudder", "Discovery+", "Criterion Channel", "Fubo", "DAZN"),
                Category.MUSIC to listOf("Spotify", "Apple Music", "Tidal", "YouTube Music", "Deezer", "Amazon Music", "SoundCloud Go", "Qobuz", "Pandora"),
                Category.AI to listOf("ChatGPT", "Claude", "Gemini", "Perplexity", "Cursor", "Midjourney", "GitHub Copilot", "Runway", "ElevenLabs", "Poe"),
                Category.GAMING to listOf("Xbox Game Pass", "PlayStation Plus", "Nintendo Switch Online", "Roblox Premium", "EA Play", "Ubisoft+", "GeForce NOW", "Apple Arcade", "Humble Choice", "Final Fantasy XIV", "World of Warcraft"),
                Category.PRIVACY to listOf("Mullvad", "Proton", "NordVPN", "Surfshark", "1Password", "Bitwarden", "addy.io", "ExpressVPN", "IVPN", "SimpleLogin", "Dashlane"),
                Category.PRODUCTIVITY to listOf("Microsoft 365", "Notion", "Adobe Creative Cloud", "Todoist", "Evernote", "Slack", "Zoom", "Canva", "Fantastical", "Things Cloud", "Grammarly", "Obsidian Sync", "Readwise", "Superhuman"),
                Category.CLOUD to listOf("iCloud+", "Google One", "Dropbox", "Box", "OneDrive", "Backblaze", "pCloud", "MEGA", "Sync.com"),
                Category.FITNESS to listOf("Apple Fitness+", "Strava", "Peloton", "Fitbod", "Headspace", "Calm", "MyFitnessPal", "Whoop", "Oura", "Nike Training", "ClassPass"),
                Category.EDUCATION to listOf("Duolingo", "Coursera", "Skillshare", "MasterClass", "Brilliant", "LinkedIn Learning", "Codecademy", "Babbel", "DataCamp", "Blinkist"),
                Category.NEWS to listOf("The New York Times", "The Washington Post", "The Economist", "The Guardian", "Financial Times", "The Wall Street Journal", "The Atlantic", "The New Yorker", "Apple News+", "The Globe and Mail"),
                Category.HOSTING to listOf("Squarespace", "Wix", "Webflow", "WordPress.com", "Ghost", "Shopify", "DigitalOcean", "Linode", "Hetzner", "Cloudflare", "Vercel", "Netlify"),
                Category.DEVELOPER to listOf("GitHub", "GitLab", "JetBrains", "Tower", "Postman", "Sentry", "Linear", "Figma", "Sketch", "Docker", "Expo", "Raycast", "Setapp"),
                Category.OTHER to listOf("Audible", "Kindle Unlimited", "Patreon", "Substack", "Amazon Prime", "Costco", "Instacart+", "Uber One", "DoorDash DashPass", "NYT Games"),
            )
            groups.flatMap { (category, names) -> names.map { ServicePreset(it, category) } }.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
        }
    }
}

enum class SubscriptionScope(val label: String) { ALL("All"), ACTIVE("Active"), PAUSED("Paused"), CANCELED("Canceled"), ARCHIVED("Archived") }
enum class SubscriptionSort(val label: String) { RENEWAL("Next renewal"), AMOUNT("Payment amount"), NAME("Name") }

@Immutable
data class SubscriptionListQuery(
    val search: String = "",
    val category: Category? = null,
    val scope: SubscriptionScope = SubscriptionScope.ALL,
    val sort: SubscriptionSort = SubscriptionSort.RENEWAL,
) {
    fun apply(records: List<SubscriptionRecord>, reportingCurrency: String, rates: ExchangeRates, today: LocalDate = LocalDate.now(), zone: ZoneId = ZoneId.systemDefault()): List<SubscriptionRecord> {
        val filtered = records.filter { record ->
            (if (scope == SubscriptionScope.ARCHIVED) record.archived else !record.archived) &&
                (scope == SubscriptionScope.ALL || scope == SubscriptionScope.ARCHIVED || record.status.label == scope.label) &&
                (category == null || record.category == category) &&
                (search.isEmpty() || record.name.contains(search, ignoreCase = true) || record.notes.contains(search, ignoreCase = true))
        }
        // Resolve recurrence/FX once per record, rather than inside the sorting comparator.
        val engine = RecurrenceEngine(zone)
        val dates = filtered.associate { it.id to (engine.nextPayment(it, today)?.date ?: LocalDate.MAX) }
        val amounts = filtered.associate { it.id to (rates.convert(it.amount, it.currency, reportingCurrency) ?: BigDecimal.ONE.negate()) }
        val byName = compareBy<SubscriptionRecord, String>(String.CASE_INSENSITIVE_ORDER) { it.name }.thenBy { it.id }
        return filtered.sortedWith(when (sort) {
            SubscriptionSort.RENEWAL -> compareBy<SubscriptionRecord> { dates.getValue(it.id) }.then(byName)
            SubscriptionSort.AMOUNT -> compareByDescending<SubscriptionRecord> { amounts.getValue(it.id) }.then(byName)
            SubscriptionSort.NAME -> byName
        })
    }
}

/** File naming, retention and freshness rules for automatic folder backups (same as iOS). */
object BackupPlan {
    const val LATEST_FILE_NAME = "Subspace Backup.json"
    const val SNAPSHOTS_KEPT = 14
    const val OVERDUE_AFTER_DAYS = 7
    private val snapshotPattern = Regex("^Subspace Backup \\d{4}-\\d{2}-\\d{2}\\.json$")

    fun snapshotName(day: LocalDate): String = "Subspace Backup $day.json"
    fun isSnapshot(name: String): Boolean = snapshotPattern.matches(name)
    /** Dated copies beyond the newest [keep], oldest first. Other files in the folder are never returned. */
    fun snapshotsToPrune(names: List<String>, keep: Int = SNAPSHOTS_KEPT): List<String> =
        names.filter(::isSnapshot).sortedDescending().drop(maxOf(keep, 0)).sorted()
    fun isDue(lastBackupMillis: Long?, nowMillis: Long = System.currentTimeMillis()): Boolean =
        lastBackupMillis == null || nowMillis - lastBackupMillis >= 86_400_000
    fun isOverdue(lastBackupMillis: Long?, today: LocalDate = LocalDate.now(), zone: ZoneId = ZoneId.systemDefault()): Boolean {
        if (lastBackupMillis == null) return true
        val day = java.time.Instant.ofEpochMilli(lastBackupMillis).atZone(zone).toLocalDate()
        return java.time.temporal.ChronoUnit.DAYS.between(day, today) >= OVERDUE_AFTER_DAYS
    }
}
