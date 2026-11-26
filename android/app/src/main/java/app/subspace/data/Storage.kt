package app.subspace.data

import android.content.Context
import android.content.SharedPreferences
import android.util.AtomicFile
import androidx.core.content.edit
import app.subspace.core.AppJson
import app.subspace.core.Backup
import app.subspace.core.ExchangeRates
import app.subspace.core.SubscriptionRecord
import java.io.File
import java.io.FileNotFoundException

/**
 * Subscriptions live in one JSON file in the app's private storage, in the same format as a backup.
 * Writes are atomic (write-new-then-rename), so a crash never leaves a half-written file, and an
 * unreadable file is reported but never deleted.
 */
class SubscriptionStore(context: Context) {
    private val file = AtomicFile(File(context.filesDir, FILE_NAME))

    /** Returns null when there is no file yet. Throws when the file exists but cannot be read. */
    fun load(): List<SubscriptionRecord>? = try {
        AppJson.decodeFromString(Backup.serializer(), file.readFully().decodeToString()).subscriptions
    } catch (_: FileNotFoundException) { null }

    fun save(records: List<SubscriptionRecord>) {
        val bytes = AppJson.encodeToString(Backup.serializer(), Backup(subscriptions = records)).encodeToByteArray()
        val stream = file.startWrite()
        try { stream.write(bytes); file.finishWrite(stream) } catch (error: Exception) { file.failWrite(stream); throw error }
    }

    companion object { const val FILE_NAME = "subscriptions.json" }
}

/** Small preferences, mirrored from the iOS app's UserDefaults keys. */
class Settings(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    var currency: String
        get() = prefs.getString("reportingCurrency", null) ?: "CAD"
        set(value) = prefs.edit { putString("reportingCurrency", value) }
    /** "dark" (default, like iOS) or "system". */
    var appearance: String
        get() = prefs.getString("appearance", null) ?: "dark"
        set(value) = prefs.edit { putString("appearance", value) }
    var remindersEnabled: Boolean
        get() = prefs.getBoolean("remindersEnabled", false)
        set(value) = prefs.edit { putBoolean("remindersEnabled", value) }
    var defaultReminder: Int
        get() = prefs.getInt("defaultReminder", 3)
        set(value) = prefs.edit { putInt("defaultReminder", value) }
    var rates: ExchangeRates
        get() = prefs.getString("exchangeRates", null)?.let { runCatching { AppJson.decodeFromString(ExchangeRates.serializer(), it) }.getOrNull() } ?: ExchangeRates()
        set(value) = prefs.edit { putString("exchangeRates", AppJson.encodeToString(ExchangeRates.serializer(), value)) }
    var backupFolder: String?
        get() = prefs.getString("backupFolder", null)
        set(value) = prefs.edit { if (value == null) remove("backupFolder") else putString("backupFolder", value) }
    var backupFolderName: String?
        get() = prefs.getString("backupFolderName", null)
        set(value) = prefs.edit { if (value == null) remove("backupFolderName") else putString("backupFolderName", value) }
    var lastBackup: Long?
        get() = prefs.getLong("lastBackup", 0).takeIf { it > 0 }
        set(value) = prefs.edit { putLong("lastBackup", value ?: 0) }
    /** Last calendar day (ISO) on which reminder notifications were posted, to avoid duplicates. */
    var lastReminderDay: String?
        get() = prefs.getString("lastReminderDay", null)
        set(value) = prefs.edit { putString("lastReminderDay", value) }
}
