package app.subspace.ui

import android.app.Application
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Immutable
import androidx.core.net.toUri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.subspace.core.AppJson
import app.subspace.core.Backup
import app.subspace.core.BackupPlan
import app.subspace.core.DataException
import app.subspace.core.ExchangeRates
import app.subspace.core.FinancialSummary
import app.subspace.core.Payment
import app.subspace.core.RecurrenceEngine
import app.subspace.core.SubscriptionRecord
import app.subspace.data.FolderBackup
import app.subspace.data.RatesService
import app.subspace.data.Settings
import app.subspace.data.SubscriptionStore
import app.subspace.reminders.Reminders
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate

/** Everything the screens read. Derived figures are computed once per change, never per frame. */
@Immutable
data class UiState(
    val loaded: Boolean = false,
    val records: List<SubscriptionRecord> = emptyList(),
    val rates: ExchangeRates = ExchangeRates(),
    val currency: String = "CAD",
    val appearance: String = "dark",
    val remindersEnabled: Boolean = false,
    val defaultReminder: Int = 3,
    val summary: FinancialSummary = FinancialSummary.of(emptyList(), "CAD", ExchangeRates()),
    /** Next payment for each active plan, soonest first. */
    val upcoming: List<Payment> = emptyList(),
    val refreshingRates: Boolean = false,
    val backupFolderName: String? = null,
    val lastBackup: Long? = null,
    val backupProblem: String? = null,
    val backingUp: Boolean = false,
    val notificationMessage: String? = null,
    val error: String? = null,
    val checkingUpdate: Boolean = false,
    val updateResult: UpdateResult? = null,
    /** A backup handed to the app by a file manager or the share sheet, waiting for confirmation. */
    val incomingImport: List<SubscriptionRecord>? = null,
) {
    val visible: List<SubscriptionRecord> get() = records.filter { !it.archived }
    fun converted(record: SubscriptionRecord) = rates.convert(record.amount, record.currency, currency)
}

/** Outcome of a manual update check. */
@Immutable
sealed interface UpdateResult {
    data class UpToDate(val version: String) : UpdateResult
    data class Available(val version: String, val url: String) : UpdateResult
    data class Failed(val message: String) : UpdateResult
}

@OptIn(ExperimentalCoroutinesApi::class)
class AppModel(application: Application) : AndroidViewModel(application) {
    private val context get() = getApplication<Application>()
    private val settings = Settings(application)
    private val store = SubscriptionStore(application)
    /** Serializes disk writes in the order they were requested. */
    private val io = Dispatchers.IO.limitedParallelism(1)
    private var backupJob: Job? = null
    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            val loaded = withContext(io) { runCatching { store.load() ?: emptyList() } }
            val records = loaded.getOrElse { emptyList() }
            _state.value = derive(UiState(
                loaded = true, records = records, rates = settings.rates, currency = settings.currency,
                appearance = settings.appearance, remindersEnabled = settings.remindersEnabled, defaultReminder = settings.defaultReminder,
                backupFolderName = settings.backupFolder?.let { settings.backupFolderName }, lastBackup = settings.lastBackup,
                error = loaded.exceptionOrNull()?.let { "Your subscriptions could not be loaded. The stored data has been preserved. ${it.message ?: ""}" },
            ))
            // Never overwrite a file that failed to load.
            if (loaded.isFailure) return@launch
            Reminders.schedule(context, settings.remindersEnabled)
            if (_state.value.rates.isStale()) refreshRates(silent = true)
            backUpIfDue()
        }
    }

    private fun derive(state: UiState): UiState {
        val engine = RecurrenceEngine()
        val today = LocalDate.now()
        return state.copy(
            summary = FinancialSummary.of(state.records, state.currency, state.rates, today),
            upcoming = state.records.mapNotNull { engine.nextPayment(it, today) }.sortedBy { it.date },
        )
    }
    private fun updateRecords(records: List<SubscriptionRecord>) {
        _state.update { derive(it.copy(records = records.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { r -> r.name }))) }
        val snapshot = _state.value.records
        viewModelScope.launch {
            val result = withContext(io) { runCatching { store.save(snapshot) } }
            result.exceptionOrNull()?.let { error -> _state.update { it.copy(error = "Your change could not be saved. ${error.message ?: ""}") } }
        }
        scheduleAutoBackup()
    }

    /** Validates and saves; returns an error message for the editor, or null on success. */
    fun save(record: SubscriptionRecord): String? = try {
        record.validate()
        updateRecords(_state.value.records.filter { it.id != record.id } + record)
        null
    } catch (error: DataException) { error.message }

    fun delete(record: SubscriptionRecord) = updateRecords(_state.value.records.filter { it.id != record.id })

    fun backupBytes(): ByteArray = AppJson.encodeToString(Backup.serializer(), Backup(subscriptions = _state.value.records)).encodeToByteArray()

    /** Parses and validates a backup without changing anything; returns its records. */
    fun readBackup(bytes: ByteArray): List<SubscriptionRecord> {
        if (bytes.size > 20_000_000) throw DataException("Backup exceeds the 20 MB import limit.")
        val backup = try { AppJson.decodeFromString(Backup.serializer(), bytes.decodeToString()) }
        catch (error: Exception) { throw DataException("This file is not a Subvelle backup. ${error.message ?: ""}") }
        return backup.validated()
    }
    /** Merges validated records: matching IDs are replaced, others kept. */
    fun importRecords(imported: List<SubscriptionRecord>) {
        val ids = imported.map { it.id }.toSet()
        updateRecords(_state.value.records.filter { it.id !in ids } + imported)
    }

    fun refreshRates(silent: Boolean = false) {
        if (_state.value.refreshingRates) return
        _state.update { it.copy(refreshingRates = true) }
        viewModelScope.launch {
            val result = withContext(Dispatchers.IO) { runCatching { RatesService.fetch() } }
            result.onSuccess { rates -> settings.rates = rates; _state.update { derive(it.copy(rates = rates)) } }
            _state.update { current ->
                current.copy(refreshingRates = false, error = if (result.isFailure && !silent) "Rates could not be refreshed. Cached rates remain available. ${result.exceptionOrNull()?.message ?: ""}" else current.error)
            }
        }
    }

    fun setCurrency(code: String) { settings.currency = code; _state.update { derive(it.copy(currency = code)) } }
    fun setAppearance(value: String) { settings.appearance = value; _state.update { it.copy(appearance = value) } }
    fun setDefaultReminder(days: Int) { settings.defaultReminder = days; _state.update { it.copy(defaultReminder = days) } }
    fun setReminders(enabled: Boolean) {
        val allowed = enabled && Reminders.canNotify(context)
        settings.remindersEnabled = allowed
        Reminders.schedule(context, allowed)
        _state.update {
            it.copy(remindersEnabled = allowed, notificationMessage = when {
                enabled && !allowed -> "Notifications are turned off for Subvelle. Allow them in Android settings to receive renewal reminders."
                allowed -> "Reminders are checked every day around 9 AM. Delivery depends on your device's battery and notification settings."
                else -> null
            })
        }
    }
    fun dismissError() = _state.update { it.copy(error = null) }

    /** Recomputes date-dependent figures (next payments, "today", active plans) after midnight or a resume. */
    fun refreshDay() = _state.update { if (it.loaded) derive(it) else it }

    /** Asks GitHub for the newest release, only when the user taps "Check for updates". */
    fun checkForUpdates(installed: String) {
        if (_state.value.checkingUpdate) return
        _state.update { it.copy(checkingUpdate = true) }
        viewModelScope.launch {
            val result = withContext(Dispatchers.IO) { runCatching { app.subspace.data.UpdateService.latest() } }
            _state.update { current ->
                current.copy(checkingUpdate = false, updateResult = result.fold(
                    onSuccess = { if (app.subspace.core.AppVersion.isNewer(it.version, installed)) UpdateResult.Available(it.version, it.url) else UpdateResult.UpToDate(installed) },
                    onFailure = { UpdateResult.Failed("Couldn’t check for updates. ${it.message ?: ""}".trim()) },
                ))
            }
        }
    }

    /** Reads and validates a backup opened from another app; asks before importing. */
    fun openIncoming(uri: android.net.Uri) {
        viewModelScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { readBackup(context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: throw DataException("The file could not be opened.")) }
            }
            result.onSuccess { records -> _state.update { it.copy(incomingImport = records) } }
                .onFailure { error -> showError((error as? DataException)?.message ?: "This backup could not be read. ${error.message ?: ""}") }
        }
    }
    fun confirmIncoming() { _state.value.incomingImport?.let(::importRecords); _state.update { it.copy(incomingImport = null) } }
    fun dismissIncoming() = _state.update { it.copy(incomingImport = null) }
    fun showError(message: String) = _state.update { it.copy(error = message) }

    // ---- Automatic folder backup ----

    fun setBackupFolder(uri: Uri) {
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        try { context.contentResolver.takePersistableUriPermission(uri, flags) } catch (_: SecurityException) {
            _state.update { it.copy(backupProblem = "Subvelle could not keep access to that folder. Choose a folder on this device or in a cloud app that supports folders.") }
            return
        }
        // Release the previous folder's permission so they don't accumulate.
        settings.backupFolder?.let { old -> if (old != uri.toString()) runCatching { context.contentResolver.releasePersistableUriPermission(old.toUri(), flags) } }
        val name = FolderBackup.displayName(context, uri)
        settings.backupFolder = uri.toString(); settings.backupFolderName = name
        _state.update { it.copy(backupFolderName = name, backupProblem = null) }
        backUpNow()
    }
    fun stopAutoBackup() {
        backupJob?.cancel()
        settings.backupFolder?.let { runCatching { context.contentResolver.releasePersistableUriPermission(it.toUri(), Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION) } }
        settings.backupFolder = null; settings.backupFolderName = null
        _state.update { it.copy(backupFolderName = null, backupProblem = null) }
    }
    fun markExported() = recordBackup()
    private fun recordBackup() {
        val now = System.currentTimeMillis()
        settings.lastBackup = now
        _state.update { it.copy(lastBackup = now) }
    }
    fun backUpIfDue() {
        val state = _state.value
        if (state.backupFolderName != null && (state.backupProblem != null || BackupPlan.isDue(state.lastBackup))) backUpNow()
    }
    fun backUpNow() {
        val folder = settings.backupFolder ?: return
        if (_state.value.backingUp) { scheduleAutoBackup(); return }
        _state.update { it.copy(backingUp = true) }
        val bytes = backupBytes()
        viewModelScope.launch {
            val result = withContext(io) { runCatching { FolderBackup.write(context, folder.toUri(), bytes) } }
            if (settings.backupFolder == null) { _state.update { it.copy(backingUp = false) }; return@launch }
            if (result.isSuccess) recordBackup()
            _state.update { it.copy(backingUp = false, backupProblem = result.exceptionOrNull()?.let { e -> "The last automatic backup failed. ${e.message ?: ""}" }) }
        }
    }
    /** Coalesces bursts of edits (for example, an import) into one backup a moment later. */
    private fun scheduleAutoBackup() {
        if (settings.backupFolder == null) return
        backupJob?.cancel()
        backupJob = viewModelScope.launch { delay(2_000); backUpNow() }
    }
}
