package app.subspace.data

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import app.subspace.core.AppJson
import app.subspace.core.BackupPlan
import app.subspace.core.DataException
import app.subspace.core.ExchangeRates
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.math.BigDecimal
import java.net.HttpURLConnection
import java.net.URL
import java.time.LocalDate
import java.time.ZoneId

/** Public central-bank reference rates from Frankfurter. Subscription data is never sent. */
object RatesService {
    private const val ENDPOINT = "https://api.frankfurter.dev/v1/latest?base=USD"

    /** Blocking; call from Dispatchers.IO. */
    fun fetch(): ExchangeRates {
        val connection = (URL(ENDPOINT).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000; readTimeout = 20_000
            setRequestProperty("Accept", "application/json")
        }
        try {
            if (connection.responseCode != 200) throw DataException("Exchange-rate provider is unavailable.")
            val body = connection.inputStream.use { it.readBytes().decodeToString() }
            val json = AppJson.parseToJsonElement(body).jsonObject
            val base = json["base"]?.jsonPrimitive?.content
            val date = json["date"]?.jsonPrimitive?.content?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
            val rates = json["rates"]?.jsonObject?.mapValues { BigDecimal(it.value.jsonPrimitive.content) }
            if (base != "USD" || date == null || rates.isNullOrEmpty() || rates.values.any { it.signum() <= 0 }) throw DataException("Invalid exchange-rate response.")
            // Frankfurter publishes a calendar date: keep it as that local day.
            return ExchangeRates("USD", rates, date.atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli())
        } finally { connection.disconnect() }
    }
}

/**
 * Writes backups into a folder the user picked with the system folder picker (Storage Access
 * Framework). The permission is persisted, so later backups need no prompt. Works with on-device
 * folders and any cloud provider whose app offers folders in the picker.
 */
object FolderBackup {
    /** Blocking; call from Dispatchers.IO. */
    fun write(context: Context, folderUri: Uri, json: ByteArray, today: LocalDate = LocalDate.now()) {
        val folder = DocumentFile.fromTreeUri(context, folderUri)
        if (folder == null || !folder.canWrite()) throw DataException("Subvelle can no longer write to the backup folder. Choose it again in Settings.")
        writeFile(context, folder, BackupPlan.LATEST_FILE_NAME, json)
        writeFile(context, folder, BackupPlan.snapshotName(today), json)
        // Pruning is best effort: a copy that cannot be removed now is retried after the next change.
        val names = folder.listFiles().mapNotNull { it.name }
        for (name in BackupPlan.snapshotsToPrune(names)) runCatching { folder.findFile(name)?.delete() }
    }
    private fun writeFile(context: Context, folder: DocumentFile, name: String, json: ByteArray) {
        val file = folder.findFile(name) ?: folder.createFile("application/json", name)
            ?: throw DataException("The backup file could not be created in that folder.")
        // "wt" truncates an existing file before writing, so a shorter backup leaves no stale tail.
        val stream = context.contentResolver.openOutputStream(file.uri, "wt") ?: throw DataException("The backup file could not be opened.")
        stream.use { it.write(json) }
    }
    /** A human-readable folder name for Settings. */
    fun displayName(context: Context, folderUri: Uri): String =
        DocumentFile.fromTreeUri(context, folderUri)?.name ?: folderUri.lastPathSegment?.substringAfterLast(':') ?: "Backup folder"
}
