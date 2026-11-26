package app.subspace.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.subspace.core.Money
import app.subspace.core.isCurrentlyActive
import java.math.BigDecimal
import java.time.LocalDate
import java.time.temporal.ChronoUnit

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun OverviewScreen(state: UiState, actions: Actions) {
    val largest = remember(state.records, state.rates, state.currency) {
        state.visible.filter { it.isCurrentlyActive() && state.converted(it) != null }
            .map { it to state.converted(it)!!.multiply(it.interval.periodsPerYear, Money.MATH) }
            .sortedByDescending { it.second }.take(3)
    }
    val money = { amount: BigDecimal -> Money.format(amount, state.currency) }
    LazyColumn(
        Modifier.fillMaxSize().testTag("overviewList"),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        val width = Modifier.widthIn(max = 700.dp).fillMaxWidth()
        if (state.visible.isEmpty()) {
            item { Column(width) { EmptyState("Make room for clarity", "Know what you pay, what’s coming next, and what you could save. Start with one subscription.", actions::add) } }
        } else {
            item(key = "monthly") {
                Column(width) {
                    Card {
                        Text("Monthly average", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(money(state.summary.monthly), style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold, modifier = Modifier.testTag("monthlyAverage"))
                        Text("Your recurring commitment, averaged over the year.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Metric("Annual average", money(state.summary.annual))
                            Metric("Weekly equivalent", money(state.summary.weekly))
                            Metric("Active plans", state.summary.activeCount.toString())
                        }
                    }
                }
            }
            item(key = "notices") { Column(width, verticalArrangement = Arrangement.spacedBy(10.dp)) { RateNotice(state); BackupNotice(state, actions::openSettings) } }
            state.upcoming.firstOrNull()?.let { next ->
                item(key = "next") {
                    Column(width) {
                        Card(onClick = { actions.open(next.subscription) }) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text("Next payment", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                                Text(countdown(next.date), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                            }
                            SubscriptionRow(next.subscription, next.date)
                        }
                    }
                }
            }
            item(key = "chart") {
                Column(width) {
                    Card {
                        SectionTitle("Your year in payments", "Scheduled charges · ${LocalDate.now().year}")
                        SpendingChart(state, compact = true)
                    }
                }
            }
            if (state.upcoming.isNotEmpty()) {
                item(key = "upcomingTitle") { Column(width) { SectionTitle("Upcoming renewals", "The next payment for each service") } }
                item(key = "upcoming") {
                    Column(width) {
                        Card { state.upcoming.take(5).forEach { SubscriptionRow(it.subscription, it.date, onClick = { actions.open(it.subscription) }) } }
                    }
                }
            }
            if (largest.isNotEmpty()) {
                item(key = "largestTitle") { Column(width) { SectionTitle("Largest expenses", "Normalized annual cost · ${state.currency}") } }
                item(key = "largest") {
                    Column(width) {
                        Card {
                            largest.forEach { (record, annual) ->
                                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    SubscriptionRow(record, null, onClick = { actions.open(record) })
                                    Text("${money(annual)} / year", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }
            }
        }
        item(key = "footer") { Column(width.testTag("overviewBottom")) { PrivacyFootnote() } }
    }
}

@Composable
private fun Metric(title: String, value: String) {
    Column {
        Text(title, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
    }
}

fun countdown(date: LocalDate): String = when (val days = ChronoUnit.DAYS.between(LocalDate.now(), date)) {
    0L -> "Today"; 1L -> "Tomorrow"; else -> "In $days days"
}

