package app.subspace.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.Code
import androidx.compose.material.icons.rounded.CreditCard
import androidx.compose.material.icons.rounded.DirectionsRun
import androidx.compose.material.icons.rounded.Dns
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.GridView
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Newspaper
import androidx.compose.material.icons.rounded.School
import androidx.compose.material.icons.rounded.Security
import androidx.compose.material.icons.rounded.SportsEsports
import androidx.compose.material.icons.rounded.Tv
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.subspace.core.BackupPlan
import app.subspace.core.Category
import app.subspace.core.Money
import app.subspace.core.SubscriptionRecord
import app.subspace.core.SubscriptionStatus
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

val MediumDate: DateTimeFormatter = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)

/** iOS stores SF Symbol names; show the closest Material icon (the data is kept unchanged). */
val SymbolChoices: List<Pair<String, ImageVector>> = listOf(
    "creditcard.fill" to Icons.Rounded.CreditCard, "play.tv.fill" to Icons.Rounded.Tv, "music.note" to Icons.Rounded.MusicNote,
    "sparkles" to Icons.Rounded.AutoAwesome, "gamecontroller.fill" to Icons.Rounded.SportsEsports, "lock.shield.fill" to Icons.Rounded.Security,
    "cloud.fill" to Icons.Rounded.Cloud, "figure.run" to Icons.Rounded.DirectionsRun, "graduationcap.fill" to Icons.Rounded.School,
    "newspaper.fill" to Icons.Rounded.Newspaper, "server.rack" to Icons.Rounded.Dns, "curlybraces" to Icons.Rounded.Code,
    "heart.fill" to Icons.Rounded.Favorite, "globe" to Icons.Rounded.Language, "checkmark.seal.fill" to Icons.Rounded.CheckCircle,
    "square.grid.2x2.fill" to Icons.Rounded.GridView,
)
private val symbolMap = SymbolChoices.toMap()

val Category.symbol: String get() = when (this) {
    Category.STREAMING -> "play.tv.fill"; Category.MUSIC -> "music.note"; Category.AI -> "sparkles"; Category.GAMING -> "gamecontroller.fill"
    Category.PRIVACY -> "lock.shield.fill"; Category.PRODUCTIVITY -> "checkmark.seal.fill"; Category.CLOUD -> "cloud.fill"; Category.FITNESS -> "figure.run"
    Category.EDUCATION -> "graduationcap.fill"; Category.NEWS -> "newspaper.fill"; Category.HOSTING -> "server.rack"; Category.DEVELOPER -> "curlybraces"
    Category.OTHER -> "square.grid.2x2.fill"
}
fun iconFor(symbol: String): ImageVector = symbolMap[symbol] ?: Icons.Rounded.CreditCard

@Composable
fun Card(modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(MaterialTheme.colorScheme.surfaceContainer)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp), content = content,
    )
}

@Composable
fun SectionTitle(title: String, subtitle: String? = null) {
    Column(Modifier.fillMaxWidth().padding(top = 4.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
        if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun ServiceIcon(record: SubscriptionRecord, size: Int = 44) {
    val initials = remember(record.name) { record.name.split(" ").filter { it.isNotEmpty() }.take(2).map { it.first() }.joinToString("").uppercase() }
    Box(
        Modifier.size(size.dp).clip(RoundedCornerShape((size * 0.3).dp)).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.14f)).clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(iconFor(record.symbol), null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size((size * 0.42).dp))
            if (initials.isNotEmpty()) Text(initials, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary, maxLines = 1)
        }
    }
}

@Composable
fun SubscriptionRow(record: SubscriptionRecord, date: LocalDate?, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    val price = remember(record.amount, record.currency) { Money.format(record.amount, record.currency) }
    val description = buildString {
        append(record.name); append(", "); append(price); append(", "); append(record.interval.label)
        if (date != null) append(", renews ${date.format(MediumDate)}")
        if (record.archived) append(", archived") else if (record.status != SubscriptionStatus.ACTIVE) append(", ${record.status.label}")
    }
    Row(
        modifier.fillMaxWidth().then(if (onClick != null) Modifier.clip(RoundedCornerShape(14.dp)).clickable(onClick = onClick) else Modifier)
            .padding(vertical = 7.dp).semantics(mergeDescendants = true) { contentDescription = description },
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        ServiceIcon(record)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                Text(record.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                Spacer(Modifier.width(8.dp))
                Text(price, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            }
            Text("${record.interval.label} · ${record.currency}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (date != null) Text("Renews ${date.format(MediumDate)}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (record.archived || record.status != SubscriptionStatus.ACTIVE) {
                Text(if (record.archived) "Archived" else record.status.label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
fun Notice(text: String, icon: ImageVector, onClick: (() -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(ChartColors.warning.copy(alpha = 0.10f))
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = ChartColors.warning, modifier = Modifier.size(18.dp))
        Text(text, style = MaterialTheme.typography.bodySmall, color = ChartColors.warning)
    }
}

@Composable
fun RateNotice(state: UiState) {
    val missing = remember(state.records, state.rates, state.currency) {
        state.records.filter { !it.archived && it.status == SubscriptionStatus.ACTIVE && state.converted(it) == null }.map { it.currency }.toSortedSet()
    }
    if (missing.isNotEmpty()) Notice("Partial totals · missing rates for ${missing.joinToString(", ")}. Refresh in Settings.", Icons.Outlined.Warning)
    else if (state.rates.isStale() && state.records.any { it.currency != state.currency }) {
        Text("Using cached rates · update in Settings", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun BackupNotice(state: UiState, openSettings: () -> Unit) {
    if (state.records.isEmpty() || (state.backupProblem == null && !BackupPlan.isOverdue(state.lastBackup))) return
    Notice(
        if (state.backupProblem != null) "Automatic backup failed · review it in Settings" else "No backup in the last ${BackupPlan.OVERDUE_AFTER_DAYS} days · set up automatic backup in Settings",
        Icons.Outlined.CloudOff, onClick = openSettings,
    )
}

@Composable
fun EmptyState(title: String, message: String, onAdd: () -> Unit) {
    Card {
        Icon(Icons.Rounded.GridView, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(36.dp))
        Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
        Text(message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Button(onClick = onAdd) { Icon(Icons.Rounded.Add, null); Spacer(Modifier.width(8.dp)); Text("Add subscription") }
    }
}

@Composable
fun PrivacyFootnote() {
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Outlined.Lock, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
        Text("Private by design. Stored on your phone.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
