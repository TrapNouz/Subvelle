package app.subspace.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.subspace.core.Category
import app.subspace.core.Money
import app.subspace.core.Payment
import app.subspace.core.RecurrenceEngine
import app.subspace.core.SubscriptionRecord
import app.subspace.core.isCurrentlyActive
import java.math.BigDecimal
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.atan2
import kotlin.math.max

// ---------------------------------------------------------------- shared calculations

/** All scheduled payments in [start, endExclusive), computed once for a whole chart. */
fun allPayments(records: List<SubscriptionRecord>, start: LocalDate, endExclusive: LocalDate): List<Payment> {
    val engine = RecurrenceEngine()
    return records.flatMap { engine.payments(it, start, endExclusive) }.sortedBy { it.date }
}
fun UiState.total(payments: List<Payment>): BigDecimal = payments.fold(BigDecimal.ZERO) { sum, p -> sum.add(converted(p.subscription) ?: BigDecimal.ZERO) }

@Immutable data class Bucket(val label: String, val longLabel: String, val total: BigDecimal, val past: Boolean)

// ---------------------------------------------------------------- spending chart

@Composable
fun SpendingChart(state: UiState, compact: Boolean = false) {
    val now = remember { LocalDate.now() }
    var year by rememberSaveable { mutableIntStateOf(now.year) }
    var month by rememberSaveable { mutableIntStateOf(now.monthValue) }
    var monthly by rememberSaveable { mutableStateOf(false) }
    var selected by remember(year, month, monthly) { mutableStateOf<Int?>(null) }
    val buckets = remember(year, month, monthly, state.records, state.rates, state.currency) {
        if (monthly) {
            val ym = YearMonth.of(year, month)
            val payments = allPayments(state.records, ym.atDay(1), ym.plusMonths(1).atDay(1)).groupBy { it.date.dayOfMonth }
            (1..ym.lengthOfMonth()).map { day ->
                val date = ym.atDay(day)
                Bucket(day.toString(), date.format(MediumDate), state.total(payments[day].orEmpty()), date.isBefore(now))
            }
        } else {
            val payments = allPayments(state.records, LocalDate.of(year, 1, 1), LocalDate.of(year + 1, 1, 1)).groupBy { it.date.monthValue }
            (1..12).map { m ->
                val ym = YearMonth.of(year, m)
                Bucket(ym.month.getDisplayName(TextStyle.NARROW, Locale.getDefault()), ym.month.getDisplayName(TextStyle.FULL, Locale.getDefault()),
                    state.total(payments[m].orEmpty()), ym.plusMonths(1).atDay(1) <= now)
            }
        }
    }
    val average = if (monthly) null else state.summary.monthly
    val total = remember(buckets) { buckets.fold(BigDecimal.ZERO) { s, b -> s.add(b.total) } }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (!compact) {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                listOf("Annual", "Monthly").forEachIndexed { index, label ->
                    SegmentedButton(selected = monthly == (index == 1), onClick = { monthly = index == 1 }, shape = SegmentedButtonDefaults.itemShape(index, 2)) { Text(label) }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { if (monthly) { if (month == 1) { month = 12; year-- } else month-- } else year-- }, enabled = year > 1900) { Icon(Icons.AutoMirrored.Rounded.KeyboardArrowLeft, "Previous period") }
                Text(if (monthly) "${YearMonth.of(year, month).month.getDisplayName(TextStyle.FULL, Locale.getDefault())} $year" else "$year",
                    style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f), textAlign = TextAlign.Center)
                IconButton(onClick = { if (monthly) { if (month == 12) { month = 1; year++ } else month++ } else year++ }, enabled = year < 2200) { Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, "Next period") }
            }
        }
        val shown = selected?.let { buckets.getOrNull(it) }
        Row(verticalAlignment = Alignment.Bottom) {
            Text(Money.format(shown?.total ?: total, state.currency), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            Text(shown?.longLabel ?: "Scheduled · ${state.currency}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        BarChart(buckets, average, selected, onSelect = { selected = if (selected == it) null else it }, modifier = Modifier.fillMaxWidth().height(if (compact) 140.dp else 210.dp).testTag("spendingChart"))
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) { Legend("Past estimate", ChartColors.past); Legend("Forecast", ChartColors.forecast) }
        if (!monthly) Text("Dashed line: current normalized monthly average. Bars: scheduled charges in each month.", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (!compact) Text("History is estimated from your current schedules, not bank transactions. Amounts use cached exchange rates.", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun BarChart(buckets: List<Bucket>, average: BigDecimal?, selected: Int?, onSelect: (Int) -> Unit, modifier: Modifier) {
    val past = ChartColors.past; val forecast = ChartColors.forecast
    val grid = MaterialTheme.colorScheme.outlineVariant; val label = MaterialTheme.colorScheme.onSurfaceVariant
    val values = remember(buckets) { buckets.map { it.total.toDouble() } }
    val maxValue = remember(values, average) { max(values.maxOrNull() ?: 0.0, average?.toDouble() ?: 0.0).takeIf { it > 0 } ?: 1.0 }
    val labelStep = if (buckets.size > 12) 5 else 1
    Column(modifier.semantics { contentDescription = "Scheduled payments chart, ${buckets.size} bars. Tap a bar to see its total." }) {
        Canvas(Modifier.fillMaxWidth().weight(1f).clipToBounds().pointerInput(buckets.size) {
            detectTapGestures { offset -> onSelect(((offset.x / size.width) * buckets.size).toInt().coerceIn(0, buckets.size - 1)) }
        }) {
            val slot = size.width / buckets.size
            val barWidth = slot * if (buckets.size > 12) 0.62f else 0.56f
            for (i in 1..3) { val y = size.height * i / 4f; drawLine(grid, Offset(0f, y), Offset(size.width, y), strokeWidth = 1f) }
            values.forEachIndexed { index, value ->
                val height = (value / maxValue * size.height).toFloat()
                if (height <= 0f) return@forEachIndexed
                val alpha = if (selected == null || selected == index) 1f else 0.35f
                drawRoundRect(
                    color = (if (buckets[index].past) past else forecast).copy(alpha = alpha),
                    topLeft = Offset(slot * index + (slot - barWidth) / 2, size.height - height),
                    size = Size(barWidth, height), cornerRadius = CornerRadius(minOf(barWidth / 2, 10f)),
                )
            }
            average?.let {
                val y = size.height - (it.toDouble() / maxValue * size.height).toFloat()
                drawLine(label, Offset(0f, y), Offset(size.width, y), strokeWidth = 2f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 8f)))
            }
        }
        Row(Modifier.fillMaxWidth().padding(top = 4.dp)) {
            buckets.forEachIndexed { index, bucket ->
                Text(if (index % labelStep == 0) bucket.label else "", style = MaterialTheme.typography.labelSmall, color = label, textAlign = TextAlign.Center, maxLines = 1, modifier = Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun Legend(text: String, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        Box(Modifier.size(7.dp).clip(CircleShape).background(color)); Text(text, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

// ---------------------------------------------------------------- analytics tab

@Immutable data class Breakdown(val name: String, val amount: BigDecimal)

@Composable
fun AnalyticsScreen(state: UiState, actions: Actions) {
    val active = remember(state.records) { state.visible.filter { it.isCurrentlyActive() } }
    fun annual(record: SubscriptionRecord) = (state.converted(record) ?: BigDecimal.ZERO).multiply(record.interval.periodsPerYear, Money.MATH)
    val categories = remember(active, state.rates, state.currency) {
        val items = Category.entries.mapNotNull { c -> active.filter { it.category == c }.fold(BigDecimal.ZERO) { s, r -> s.add(annual(r)) }.takeIf { it.signum() > 0 }?.let { Breakdown(c.label, it) } }
            .sortedByDescending { it.amount }
        val rest = items.drop(5).fold(BigDecimal.ZERO) { s, b -> s.add(b.amount) }
        items.take(5) + if (rest.signum() > 0) listOf(Breakdown("Other categories", rest)) else emptyList()
    }
    val ranked = remember(active, state.rates, state.currency) { active.filter { state.converted(it) != null }.map { it to annual(it) }.sortedByDescending { it.second } }
    val currencies = remember(active, state.rates, state.currency) {
        active.map { it.currency }.toSortedSet().map { code -> Breakdown(code, active.filter { it.currency == code }.fold(BigDecimal.ZERO) { s, r -> s.add(annual(r)) }) }.filter { it.amount.signum() > 0 }
    }
    LazyColumn(Modifier.fillMaxSize().testTag("analyticsList"), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(18.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        val width = Modifier.widthIn(max = 700.dp).fillMaxWidth()
        if (state.visible.isEmpty()) {
            item { Column(width) { EmptyState("See the bigger picture", "Add a subscription to see scheduled payments, average costs, and where your money goes.", actions::add) } }
        } else {
            item(key = "rates") { Column(width) { RateNotice(state) } }
            item(key = "chart") { Column(width) { Card { SpendingChart(state) } } }
            if (active.isEmpty()) {
                item { Column(width) { Card { Text("No active commitments. Paused and canceled records are excluded.", color = MaterialTheme.colorScheme.onSurfaceVariant) } } }
            } else {
                item(key = "catTitle") { Column(width) { SectionTitle("Where it goes", "Normalized annual cost by category") } }
                item(key = "cat") { Column(width) { Card { if (categories.isEmpty()) Text("Refresh exchange rates to show this breakdown.") else DonutChart(categories, state.currency) } } }
                item(key = "svcTitle") { Column(width) { SectionTitle("By subscription", "Normalized annual cost · ${state.currency}") } }
                item(key = "svc") {
                    Column(width) {
                        Card {
                            val top = ranked.firstOrNull()?.second?.toDouble()?.takeIf { it > 0 } ?: 1.0
                            ranked.forEach { (record, amount) ->
                                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable { actions.open(record) }.padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Row { Text(record.name, modifier = Modifier.weight(1f)); Text(Money.format(amount, state.currency), fontWeight = FontWeight.SemiBold) }
                                    LinearProgressIndicator(progress = { (amount.toDouble() / top).toFloat() }, modifier = Modifier.fillMaxWidth(), color = ChartColors.forecast, trackColor = MaterialTheme.colorScheme.surfaceContainerHighest, drawStopIndicator = {})
                                }
                            }
                            if (ranked.isEmpty()) Text("No converted amounts available.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                item(key = "curTitle") { Column(width) { SectionTitle("Across currencies", "Converted annual costs by original billing currency") } }
                item(key = "cur") {
                    Column(width) {
                        Card {
                            val sum = currencies.sumOf { it.amount.toDouble() }.takeIf { it > 0 } ?: 1.0
                            currencies.forEach { item ->
                                Row { Text(item.name, modifier = Modifier.weight(1f)); Text(Money.format(item.amount, state.currency), fontWeight = FontWeight.SemiBold) }
                                LinearProgressIndicator(progress = { (item.amount.toDouble() / sum).toFloat() }, modifier = Modifier.fillMaxWidth(), color = ChartColors.past, trackColor = MaterialTheme.colorScheme.surfaceContainerHighest, drawStopIndicator = {})
                            }
                            if (currencies.isEmpty()) Text("Exchange rates are needed for this breakdown.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            item(key = "how") {
                Column(width) {
                    Card {
                        Text("How these figures work", fontWeight = FontWeight.SemiBold)
                        Text("Bars show scheduled charges. The dashed line shows today’s normalized monthly average. Past payments are estimates reconstructed from current schedules, using cached exchange rates. Editing or archiving a plan recalculates these estimates.",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        item(key = "calendar") {
            FilledTonalButton(onClick = actions::calendar, modifier = Modifier.testTag("analyticsBottom")) {
                Icon(Icons.Rounded.CalendarMonth, null); Spacer(Modifier.size(8.dp)); Text("Payment calendar")
            }
        }
    }
}

@Composable
private fun DonutChart(items: List<Breakdown>, currency: String) {
    val palette = listOf(MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.secondary, Color(0xFF34C3A0), Color(0xFFFFB86B), Color(0xFFFF7EB6), MaterialTheme.colorScheme.outline)
    var selected by remember(items) { mutableStateOf<Int?>(null) }
    val total = remember(items) { items.sumOf { it.amount.toDouble() } }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.fillMaxWidth().heightIn(max = 230.dp).aspectRatio(1.6f), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize().semantics { contentDescription = "Annual cost by category. Tap a segment for its total." }.pointerInput(items) {
                detectTapGestures { offset ->
                    val angle = (Math.toDegrees(atan2((offset.y - size.height / 2).toDouble(), (offset.x - size.width / 2).toDouble())) + 450) % 360
                    var running = 0.0
                    val index = items.indexOfFirst { running += it.amount.toDouble() / total * 360; angle < running }
                    selected = if (selected == index) null else index.takeIf { it >= 0 }
                }
            }) {
                val diameter = minOf(size.width, size.height) * 0.92f
                val stroke = diameter * 0.16f
                val topLeft = Offset((size.width - diameter) / 2 + stroke / 2, (size.height - diameter) / 2 + stroke / 2)
                val arcSize = Size(diameter - stroke, diameter - stroke)
                var start = -90f
                items.forEachIndexed { index, item ->
                    val sweep = (item.amount.toDouble() / total * 360).toFloat()
                    val alpha = if (selected == null || selected == index) 1f else 0.35f
                    drawArc(palette[index % palette.size].copy(alpha = alpha), start + 1.5f, (sweep - 3f).coerceAtLeast(0.5f), false, topLeft, arcSize, style = Stroke(stroke, cap = StrokeCap.Butt))
                    start += sweep
                }
            }
            selected?.let { items.getOrNull(it) }?.let {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(it.name, style = MaterialTheme.typography.labelMedium); Text(Money.format(it.amount, currency), fontWeight = FontWeight.Bold)
                }
            }
        }
        items.forEachIndexed { index, item ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.size(9.dp).clip(CircleShape).background(palette[index % palette.size]))
                Text(item.name, modifier = Modifier.weight(1f)); Text(Money.format(item.amount, currency), fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

// ---------------------------------------------------------------- payment calendar

@Composable
fun PaymentCalendar(state: UiState, actions: Actions) {
    val today = remember { LocalDate.now() }
    var cursor by rememberSaveable { mutableStateOf(YearMonth.from(today).toString()) }
    val month = YearMonth.parse(cursor)
    var selectedDay by rememberSaveable { mutableStateOf(today.toString()) }
    var annual by rememberSaveable { mutableStateOf(false) }
    val payments = remember(month, annual, state.records) {
        if (annual) allPayments(state.records, LocalDate.of(month.year, 1, 1), LocalDate.of(month.year + 1, 1, 1))
        else allPayments(state.records, month.atDay(1), month.plusMonths(1).atDay(1))
    }
    FullScreen("Payment calendar", onDismiss = actions::close) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            item {
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    listOf("Month", "Year").forEachIndexed { i, label -> SegmentedButton(annual == (i == 1), { annual = i == 1 }, SegmentedButtonDefaults.itemShape(i, 2)) { Text(label) } }
                }
            }
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { cursor = (if (annual) month.minusYears(1) else month.minusMonths(1)).toString() }) { Icon(Icons.AutoMirrored.Rounded.KeyboardArrowLeft, "Previous period") }
                    Text(if (annual) "${month.year}" else "${month.month.getDisplayName(TextStyle.FULL, Locale.getDefault())} ${month.year}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
                    IconButton(onClick = { cursor = (if (annual) month.plusYears(1) else month.plusMonths(1)).toString() }) { Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, "Next period") }
                }
            }
            item { RateNotice(state) }
            if (annual) {
                val byMonth = payments.groupBy { it.date.monthValue }
                item {
                    LazyVerticalGrid(GridCells.Fixed(2), Modifier.fillMaxWidth().heightIn(max = 2000.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp), userScrollEnabled = false) {
                        items((1..12).toList(), key = { it }) { m ->
                            val list = byMonth[m].orEmpty()
                            Card(onClick = { cursor = YearMonth.of(month.year, m).toString(); selectedDay = YearMonth.of(month.year, m).atDay(1).toString(); annual = false }) {
                                Text(YearMonth.of(month.year, m).month.getDisplayName(TextStyle.FULL, Locale.getDefault()), fontWeight = FontWeight.SemiBold)
                                Text(Money.format(state.total(list), state.currency), color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold)
                                Text("${list.size} payments", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            } else {
                val byDay = payments.groupBy { it.date.dayOfMonth }
                val selected = LocalDate.parse(selectedDay)
                item { Card { MonthGrid(month, byDay.keys, selected) { selectedDay = it.toString() } } }
                val dayPayments = if (YearMonth.from(selected) == month) byDay[selected.dayOfMonth].orEmpty() else emptyList()
                item { SectionTitle(selected.format(java.time.format.DateTimeFormatter.ofPattern("EEEE, MMMM d")), "${dayPayments.size} scheduled payments · ${Money.format(state.total(dayPayments), state.currency)}") }
                item {
                    if (dayPayments.isEmpty()) Text("A quiet day. No subscription payments are scheduled.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    else Card { dayPayments.forEach { SubscriptionRow(it.subscription, it.date, onClick = { actions.open(it.subscription) }) } }
                }
            }
            item { Text("Calendar amounts are scheduled estimates, not confirmed bank transactions. Past dates are reconstructed from your current schedules.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
}

@Composable
private fun MonthGrid(month: YearMonth, paymentDays: Set<Int>, selected: LocalDate, onSelect: (LocalDate) -> Unit) {
    val firstDayOfWeek = java.time.temporal.WeekFields.of(Locale.getDefault()).firstDayOfWeek
    val offset = (month.atDay(1).dayOfWeek.value - firstDayOfWeek.value + 7) % 7
    val cells = offset + month.lengthOfMonth()
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row { (0 until 7).forEach { i -> Text(firstDayOfWeek.plus(i.toLong()).getDisplayName(TextStyle.NARROW, Locale.getDefault()), Modifier.weight(1f), textAlign = TextAlign.Center, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
        (0 until (cells + 6) / 7).forEach { week ->
            Row {
                (0 until 7).forEach { col ->
                    val day = week * 7 + col - offset + 1
                    if (day < 1 || day > month.lengthOfMonth()) Spacer(Modifier.weight(1f).height(48.dp))
                    else {
                        val date = month.atDay(day)
                        val isSelected = date == selected
                        Column(
                            Modifier.weight(1f).height(48.dp).clip(RoundedCornerShape(12.dp)).background(if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = 0.22f) else Color.Transparent)
                                .clickable { onSelect(date) }.semantics { contentDescription = "${date.format(MediumDate)}${if (day in paymentDays) ", has payments" else ""}" },
                            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                        ) {
                            Text("$day", fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal)
                            Box(Modifier.size(5.dp).clip(CircleShape).background(if (day in paymentDays) MaterialTheme.colorScheme.primary else Color.Transparent))
                        }
                    }
                }
            }
        }
    }
}
