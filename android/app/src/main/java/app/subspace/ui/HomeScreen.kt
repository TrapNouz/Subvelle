package app.subspace.ui

import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.CloudDone
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.LibraryAdd
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import app.subspace.core.Money
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * One home screen with four folders. A folder pops out of its tile into a rounded panel over the
 * blurred home screen (Android 12+; older versions dim it instead). Close with ✕, a tap outside,
 * a swipe down on the handle, or Back.
 */
@Composable
fun FolderHome(state: UiState, model: AppModel, actions: Actions, openFolder: Tab?, onOpen: (Tab) -> Unit, onClose: () -> Unit) {
    val tiles = remember { mutableStateMapOf<Tab, Rect>() }
    var rootSize by remember { mutableStateOf(IntSize.Zero) }
    // Keeps the last folder's content on screen while its panel animates closed.
    var shown by remember { mutableStateOf(openFolder ?: Tab.OVERVIEW) }
    if (openFolder != null) shown = openFolder
    val open = openFolder != null
    val blur by animateDpAsState(if (open) 20.dp else 0.dp, label = "blur")
    val homeScale by animateFloatAsState(if (open) 0.95f else 1f, label = "homeScale")
    val origin = tiles[shown]?.let { tile ->
        if (rootSize.width > 0 && rootSize.height > 0) TransformOrigin(tile.center.x / rootSize.width, tile.center.y / rootSize.height) else null
    } ?: TransformOrigin.Center

    BackHandler(enabled = open, onBack = onClose)
    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).onSizeChanged { rootSize = it }) {
        Box(
            Modifier.fillMaxSize()
                .graphicsLayer { scaleX = homeScale; scaleY = homeScale }
                .then(if (Build.VERSION.SDK_INT >= 31) Modifier.blur(blur) else Modifier)
                // Hidden from screen readers and taps while a folder is open.
                .then(if (open) Modifier.clearAndSetSemantics { } else Modifier),
        ) {
            HomeScreen(state, actions, onOpen = onOpen, onTile = { tab, rect -> tiles[tab] = rect })
        }
        AnimatedVisibility(visible = open, enter = fadeIn(), exit = fadeOut()) {
            Box(
                Modifier.fillMaxSize().background(Color.Black.copy(alpha = if (Build.VERSION.SDK_INT >= 31) 0.28f else 0.55f))
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClickLabel = "Close folder", onClick = onClose)
                    .testTag("folderBackdrop"),
            )
        }
        AnimatedVisibility(
            visible = open,
            enter = scaleIn(spring(dampingRatio = 0.82f, stiffness = Spring.StiffnessMediumLow), initialScale = 0.2f, transformOrigin = origin) + fadeIn(),
            exit = scaleOut(spring(dampingRatio = 1f, stiffness = Spring.StiffnessMedium), targetScale = 0.2f, transformOrigin = origin) + fadeOut(),
        ) {
            FolderPanel(shown, state, model, actions, onClose)
        }
    }
}

@Composable
private fun HomeScreen(state: UiState, actions: Actions, onOpen: (Tab) -> Unit, onTile: (Tab, Rect) -> Unit) {
    val today = remember { LocalDate.now() }
    LazyColumn(
        Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).testTag("homeList"),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        val width = Modifier.widthIn(max = 700.dp).fillMaxWidth()
        item(key = "header") {
            Row(width, verticalAlignment = Alignment.CenterVertically) {
                Icon(androidx.compose.ui.res.painterResource(app.subspace.R.drawable.subvelle_mark), null, tint = androidx.compose.ui.graphics.Color.Unspecified, modifier = Modifier.size(46.dp))
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text("Subvelle", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
                    Text(today.format(DateTimeFormatter.ofPattern("EEEE, MMMM d")), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                FilledTonalIconButton(onClick = actions::add, modifier = Modifier.size(48.dp).testTag("addSubscription")) { Icon(Icons.Rounded.Add, "Add subscription") }
            }
        }
        item(key = "notices") { Column(width, verticalArrangement = Arrangement.spacedBy(10.dp)) { RateNotice(state); BackupNotice(state) { onOpen(Tab.SETTINGS) } } }
        item(key = "folders") {
            Column(width, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Tab.entries.chunked(2).forEach { pair ->
                    Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        pair.forEach { tab ->
                            FolderTile(tab, state, Modifier.weight(1f).onGloballyPositioned { onTile(tab, it.boundsInRoot()) }) { onOpen(tab) }
                        }
                    }
                }
            }
        }
        state.upcoming.firstOrNull()?.let { next ->
            item(key = "next") {
                Column(width) {
                    Card(onClick = { onOpen(Tab.OVERVIEW) }) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Next payment", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                            Text(countdown(next.date), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                        }
                        SubscriptionRow(next.subscription, next.date)
                    }
                }
            }
        }
        item(key = "footer") { Column(width.testTag("homeBottom")) { PrivacyFootnote() } }
    }
}

@Composable
private fun FolderTile(tab: Tab, state: UiState, modifier: Modifier, onClick: () -> Unit) {
    val summary = when (tab) {
        Tab.OVERVIEW -> "${Money.format(state.summary.monthly, state.currency)} per month"
        Tab.SUBSCRIPTIONS -> "${state.visible.size} subscriptions"
        Tab.ANALYTICS -> "Charts and payment calendar"
        Tab.SETTINGS -> if (state.backupFolderName == null) "Currency, reminders and backups" else "Automatic backup on"
    }
    val shape = RoundedCornerShape(28.dp)
    Column(
        modifier.aspectRatio(1f).clip(shape).background(MaterialTheme.colorScheme.surfaceContainer)
            .border(1.dp, Color.White.copy(alpha = 0.05f), shape)
            .clickable(onClickLabel = "Open ${tab.title}", onClick = onClick)
            .padding(16.dp)
            .semantics(mergeDescendants = true) { contentDescription = "${tab.title}, $summary" }
            .testTag("folder-${tab.name.lowercase()}"),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(Modifier.weight(1f).fillMaxWidth()) { FolderPreview(tab, state) }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(tab.icon, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
            Text(tab.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun BoxScope.FolderPreview(tab: Tab, state: UiState) {
    when (tab) {
        Tab.OVERVIEW -> Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("Monthly", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(Money.format(state.summary.monthly, state.currency), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("${state.summary.activeCount} active", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Tab.SUBSCRIPTIONS -> {
            val shown = state.visible.take(9)
            if (shown.isEmpty()) Icon(Icons.Rounded.LibraryAdd, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(34.dp))
            else Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                shown.chunked(3).forEach { row -> Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { row.forEach { ServiceIcon(it, size = 28) } } }
            }
        }
        Tab.ANALYTICS -> MiniYearChart(state, Modifier.align(Alignment.BottomStart))
        Tab.SETTINGS -> Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Rounded.Settings, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(32.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Icon(if (state.backupFolderName == null) Icons.Outlined.CloudOff else Icons.Rounded.CloudDone, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(14.dp))
                Text(if (state.backupFolderName == null) "Backup off" else "Backup on", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(state.currency, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Twelve small bars: scheduled payments in each month of the current year. */
@Composable
private fun MiniYearChart(state: UiState, modifier: Modifier) {
    val now = remember { LocalDate.now() }
    val totals = remember(state.records, state.rates, state.currency) {
        val byMonth = allPayments(state.records, LocalDate.of(now.year, 1, 1), LocalDate.of(now.year + 1, 1, 1)).groupBy { it.date.monthValue }
        (1..12).map { state.total(byMonth[it].orEmpty()).toDouble() }
    }
    val top = (totals.maxOrNull() ?: 0.0).coerceAtLeast(1.0)
    Row(modifier.fillMaxWidth().height(58.dp), horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.Bottom) {
        totals.forEachIndexed { index, value ->
            Box(Modifier.weight(1f).height((58 * value / top).coerceAtLeast(4.0).dp).clip(RoundedCornerShape(3.dp))
                .background(if (index + 1 < now.monthValue) ChartColors.past else ChartColors.forecast))
        }
    }
}

@Composable
private fun FolderPanel(tab: Tab, state: UiState, model: AppModel, actions: Actions, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    val drag = remember { Animatable(0f) }
    val shape = RoundedCornerShape(30.dp)
    Column(
        // Real margins: the blurred home screen frames the open folder and can be tapped to close it.
        Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).padding(start = 14.dp, end = 14.dp, top = 24.dp, bottom = 14.dp)
            .graphicsLayer {
                translationY = drag.value
                val s = 1f - drag.value.coerceAtMost(900f) / 9000f
                scaleX = s; scaleY = s
            }
            .shadow(24.dp, shape).clip(shape).background(MaterialTheme.colorScheme.background)
            .testTag("folderPanel"),
    ) {
        Box(
            Modifier.fillMaxWidth().height(20.dp).draggable(
                orientation = Orientation.Vertical,
                state = rememberDraggableState { delta -> scope.launch { drag.snapTo((drag.value + delta).coerceAtLeast(0f)) } },
                onDragStopped = { velocity -> if (drag.value > 300f || velocity > 2500f) onClose() else drag.animateTo(0f) },
            ),
            contentAlignment = Alignment.Center,
        ) { Box(Modifier.size(width = 40.dp, height = 5.dp).clip(CircleShape).background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f))) }
        Row(Modifier.fillMaxWidth().padding(horizontal = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onClose, modifier = Modifier.testTag("closeFolder")) { Icon(Icons.Rounded.Close, "Close") }
            Text(tab.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f).semantics { heading() }.testTag("folderTitle"))
            IconButton(onClick = actions::add, modifier = Modifier.testTag("folderAddSubscription")) { Icon(Icons.Rounded.Add, "Add subscription") }
        }
        Box(Modifier.weight(1f).fillMaxWidth()) {
            when (tab) {
                Tab.OVERVIEW -> OverviewScreen(state, actions)
                Tab.SUBSCRIPTIONS -> SubscriptionsScreen(state, model, actions)
                Tab.ANALYTICS -> AnalyticsScreen(state, actions)
                Tab.SETTINGS -> SettingsScreen(state, model)
            }
        }
    }
}

