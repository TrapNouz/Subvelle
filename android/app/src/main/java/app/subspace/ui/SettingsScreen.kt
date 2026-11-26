package app.subspace.ui

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings as AndroidSettings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.rounded.Backup
import androidx.compose.material.icons.rounded.CreateNewFolder
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.FolderOpen
import androidx.compose.material.icons.rounded.NotificationsActive
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Upload
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import app.subspace.BuildConfig
import app.subspace.core.BackupPlan
import app.subspace.core.Currencies
import app.subspace.core.DataException
import app.subspace.core.SubscriptionRecord
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

@Composable
fun SettingsScreen(state: UiState, model: AppModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var currencyPicker by remember { mutableStateOf(false) }
    var pendingImport by remember { mutableStateOf<List<SubscriptionRecord>?>(null) }
    var result by remember { mutableStateOf<String?>(null) }
    var confirmStop by remember { mutableStateOf(false) }
    var privacy by remember { mutableStateOf(false) }

    val notificationPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { model.setReminders(true) }
    val exporter = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        val bytes = model.backupBytes()
        scope.launch {
            val outcome = withContext(Dispatchers.IO) { runCatching { context.contentResolver.openOutputStream(uri, "wt")!!.use { it.write(bytes) } } }
            outcome.onSuccess { result = "Backup exported."; model.markExported() }.onFailure { model.showError(it.message ?: "The backup could not be saved.") }
        }
    }
    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val outcome = withContext(Dispatchers.IO) { runCatching { model.readBackup(context.contentResolver.openInputStream(uri)!!.use { it.readBytes() }) } }
            outcome.onSuccess { pendingImport = it }.onFailure { model.showError((it as? DataException)?.message ?: "This backup could not be read. ${it.message ?: ""}") }
        }
    }
    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri: Uri? -> uri?.let(model::setBackupFolder) }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp).testTag("settingsScroll"), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        FormSection("General") {
            SettingRow("Active subscriptions", state.summary.activeCount.toString())
            SettingRow("About Subvelle") { privacy = true }
        }
        FormSection("Currency & exchange rates", "Cached for offline use. Missing currency pairs are excluded from totals and flagged.") {
            SettingRow("Reporting currency", "${state.currency} · ${Currencies.name(state.currency)}") { currencyPicker = true }
            SettingRow("Rates updated", if (state.rates.hasRates) Instant.ofEpochMilli(state.rates.updatedAt).atZone(ZoneId.systemDefault()).toLocalDate().format(MediumDate) else "No cached rates yet")
            if (state.rates.isStale() && state.rates.hasRates) Text("Rates may be out of date", style = MaterialTheme.typography.bodySmall, color = ChartColors.warning)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) { SettingRow("Refresh rates", icon = Icons.Rounded.Refresh, onClick = if (state.refreshingRates) null else ({ model.refreshRates() })) }
                if (state.refreshingRates) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
            }
        }
        FormSection("Appearance") {
            ChoiceRow("Theme", if (state.appearance == "dark") "Dark" else "Follow system", listOf("Dark", "Follow system")) { model.setAppearance(if (it == 0) "dark" else "system") }
        }
        FormSection("Notifications", "Checked every day around 9 AM local time. Defaults apply to new plans.") {
            SwitchRow("Renewal reminders", state.remindersEnabled, Modifier.testTag("renewalReminders")) { enabled ->
                if (enabled && Build.VERSION.SDK_INT >= 33) notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS) else model.setReminders(enabled)
            }
            ChoiceRow("Default notice", "${state.defaultReminder} days before", listOf(1, 3, 7, 14).map { "$it days before" }) { model.setDefaultReminder(listOf(1, 3, 7, 14)[it]) }
            state.notificationMessage?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            SettingRow("Android notification settings", icon = Icons.Rounded.NotificationsActive) {
                context.startActivity(Intent(AndroidSettings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(AndroidSettings.EXTRA_APP_PACKAGE, context.packageName))
            }
        }
        FormSection("Backup & restore", "JSON backups include all plans and work with Subvelle on iPhone too. Import replaces matching IDs and keeps other plans. Export a recovery copy first.") {
            SettingRow("Export backup", icon = Icons.Rounded.Upload) { exporter.launch("Subvelle-${LocalDate.now()}.json") }
            SettingRow("Import backup", icon = Icons.Rounded.Download) { importer.launch(arrayOf("application/json", "application/octet-stream", "text/plain")) }
            result?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        FormSection("Automatic backup",
            "Choose a folder, for example Documents/Subvelle or a folder in a cloud storage app that appears in the picker. After every change, Subvelle saves “${BackupPlan.LATEST_FILE_NAME}” there and keeps ${BackupPlan.SNAPSHOTS_KEPT} daily copies. To restore, use Import backup. Your subscriptions are also included in Android’s own device backup when it is turned on.") {
            val folder = state.backupFolderName
            if (folder == null) {
                SettingRow("Choose backup folder", icon = Icons.Rounded.CreateNewFolder) { folderPicker.launch(null) }
            } else {
                SettingRow("Folder", folder)
                SettingRow("Last backup", state.lastBackup?.let { android.text.format.DateUtils.getRelativeTimeSpanString(it).toString() } ?: "Not yet")
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) { SettingRow("Back up now", icon = Icons.Rounded.Backup, onClick = if (state.backingUp) null else model::backUpNow) }
                    if (state.backingUp) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                }
                SettingRow("Change folder", icon = Icons.Rounded.FolderOpen) { folderPicker.launch(null) }
                SettingRow("Turn off automatic backup", icon = Icons.Outlined.CloudOff) { confirmStop = true }
            }
            state.backupProblem?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = ChartColors.warning) }
        }
        FormSection("Privacy & information") {
            SettingRow("On-device storage · No accounts, ads, or tracking")
            SettingRow("Data & privacy details") { privacy = true }
            SettingRow("Version", BuildConfig.VERSION_NAME)
            Text("Built for a clearer financial orbit.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.testTag("settingsBottom"))
        }
        Spacer(Modifier.height(16.dp))
    }

    if (currencyPicker) CurrencyPicker("Reporting currency", state.currency, onDismiss = { currencyPicker = false }) { model.setCurrency(it); currencyPicker = false }
    pendingImport?.let { records ->
        AlertDialog(
            onDismissRequest = { pendingImport = null },
            title = { Text("Import ${records.size} subscriptions?") },
            text = { Text("Matching IDs will be replaced. Export a backup first if needed.") },
            confirmButton = { TextButton(onClick = { model.importRecords(records); result = "Imported ${records.size} subscriptions."; pendingImport = null }) { Text("Merge backup") } },
            dismissButton = { TextButton(onClick = { pendingImport = null }) { Text("Cancel") } },
        )
    }
    if (confirmStop) AlertDialog(
        onDismissRequest = { confirmStop = false },
        title = { Text("Turn off automatic backup?") }, text = { Text("Existing backup files stay in the folder.") },
        confirmButton = { TextButton(onClick = { model.stopAutoBackup(); confirmStop = false }) { Text("Turn off", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = { confirmStop = false }) { Text("Cancel") } },
    )
    if (privacy) AlertDialog(
        onDismissRequest = { privacy = false }, title = { Text("Data & privacy") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Subvelle tracks your subscriptions locally. It does not connect to banks or cancel services. Pausing or canceling a record changes your tracking only.")
                Text("The only network request fetches public central-bank reference rates from Frankfurter. Your subscriptions are never included.")
                Text("Backups are JSON files with readable financial data. Automatic backups are written only to the folder you choose. Android’s device backup may include app data according to your phone’s settings.")
                Text("Reminders are local notifications, checked daily. Delivery depends on your device’s notification and battery settings.")
            }
        },
        confirmButton = { TextButton(onClick = { privacy = false }) { Text("Done") } },
    )
}
