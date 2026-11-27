package app.subspace.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.BarChart
import androidx.compose.material.icons.rounded.GridView
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.ViewAgenda
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.subspace.core.SubscriptionRecord

class MainActivity : ComponentActivity() {
    private val model: AppModel by viewModels()

    fun incoming(uri: android.net.Uri) = model.openIncoming(uri)

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        handleIncoming(intent)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) handleIncoming(intent)
        setContent {
            val state by model.state.collectAsStateWithLifecycle()
            SubspaceTheme(state.appearance) { AppRoot(state, model) }
        }
    }
}

/** Hands a backup from "Open with" or "Share" to the model, which asks before importing. */
private fun MainActivity.handleIncoming(intent: android.content.Intent?) {
    val uri = when (intent?.action) {
        android.content.Intent.ACTION_VIEW -> intent.data
        android.content.Intent.ACTION_SEND -> androidx.core.content.IntentCompat.getParcelableExtra(intent, android.content.Intent.EXTRA_STREAM, android.net.Uri::class.java)
        else -> null
    } ?: return
    incoming(uri)
}

enum class Tab(val title: String, val icon: ImageVector) {
    OVERVIEW("Overview", Icons.Rounded.GridView), SUBSCRIPTIONS("Subscriptions", Icons.Rounded.ViewAgenda),
    ANALYTICS("Analytics", Icons.Rounded.BarChart), SETTINGS("Settings", Icons.Rounded.Settings),
}

/**
 * Which modal is open, one at a time like the iOS sheets. Each remembers where "back" goes:
 * cancelling a new plan's editor returns to the service list, editing from details returns to
 * details, and details opened from the calendar return to the calendar.
 */
sealed interface Modal {
    val back: Modal?
    data object Presets : Modal { override val back: Modal? = null }
    data class Editor(val record: SubscriptionRecord, val isNew: Boolean, override val back: Modal?) : Modal
    data class Detail(val id: String, override val back: Modal?) : Modal
    data object Calendar : Modal { override val back: Modal? = null }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppRoot(state: UiState, model: AppModel) {
    var tab by rememberSaveable { mutableStateOf(Tab.OVERVIEW) }
    var modal by remember { mutableStateOf<Modal?>(null) }
    val actions = remember(model) {
        object : Actions {
            override fun add() { modal = Modal.Presets }
            override fun open(record: SubscriptionRecord) { modal = Modal.Detail(record.id, back = modal as? Modal.Calendar) }
            override fun edit(record: SubscriptionRecord) { modal = Modal.Editor(record, isNew = false, back = modal) }
            override fun create(record: SubscriptionRecord) { modal = Modal.Editor(record, isNew = true, back = Modal.Presets) }
            override fun calendar() { modal = Modal.Calendar }
            override fun close() { modal = modal?.back }
            override fun saved() { modal = (modal as? Modal.Editor)?.let { if (it.isNew) null else it.back } }
            override fun openSettings() { modal = null; tab = Tab.SETTINGS }
        }
    }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { model.backUpIfDue() }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(tab.title, fontWeight = FontWeight.Bold) },
                actions = { IconButton(onClick = actions::add, modifier = Modifier.testTag("addSubscription")) { Icon(Icons.Rounded.Add, "Add subscription") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
        bottomBar = {
            NavigationBar(containerColor = MaterialTheme.colorScheme.surfaceContainerLow) {
                Tab.entries.forEach { item ->
                    NavigationBarItem(
                        selected = tab == item, onClick = { tab = item },
                        icon = { Icon(item.icon, null) }, label = { Text(item.title) },
                        modifier = Modifier.testTag("tab-${item.name.lowercase()}"),
                    )
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            if (state.loaded) when (tab) {
                Tab.OVERVIEW -> OverviewScreen(state, actions)
                Tab.SUBSCRIPTIONS -> SubscriptionsScreen(state, model, actions)
                Tab.ANALYTICS -> AnalyticsScreen(state, actions)
                Tab.SETTINGS -> SettingsScreen(state, model)
            }
        }
    }

    when (val current = modal) {
        Modal.Presets -> PresetPicker(state, onDismiss = actions::close, onPick = actions::create)
        is Modal.Editor -> SubscriptionEditor(current.record, current.isNew, state, model, onDismiss = actions::close, onSaved = actions::saved)
        is Modal.Detail -> state.records.firstOrNull { it.id == current.id }?.let { SubscriptionDetail(it, state, model, actions) }
            ?: LaunchedEffect(current.id) { actions.close() }
        Modal.Calendar -> PaymentCalendar(state, actions)
        null -> Unit
    }

    state.incomingImport?.let { records ->
        AlertDialog(
            onDismissRequest = model::dismissIncoming,
            title = { Text("Import ${records.size} subscriptions?") },
            text = { Text("From a Subvelle backup file. Matching subscriptions will be replaced and others kept.") },
            confirmButton = { TextButton(onClick = { model.confirmIncoming(); tab = Tab.SUBSCRIPTIONS }) { Text("Merge backup") } },
            dismissButton = { TextButton(onClick = model::dismissIncoming) { Text("Cancel") } },
        )
    }
    state.error?.let { message ->
        AlertDialog(
            onDismissRequest = model::dismissError, title = { Text("Subvelle") }, text = { Text(message) },
            confirmButton = { TextButton(onClick = model::dismissError) { Text("OK") } },
        )
    }
}

/** Navigation callbacks shared by the screens; stable, so screens skip recomposition when unrelated state changes. */
interface Actions {
    fun add()
    fun open(record: SubscriptionRecord)
    fun edit(record: SubscriptionRecord)
    fun create(record: SubscriptionRecord)
    fun calendar()
    fun close()
    fun saved()
    fun openSettings()
}
