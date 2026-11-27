package app.subspace.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Archive
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.FilterList
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.SwapVert
import androidx.compose.material.icons.rounded.Unarchive
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.subspace.core.BillingInterval
import app.subspace.core.BillingUnit
import app.subspace.core.Category
import app.subspace.core.Currencies
import app.subspace.core.Money
import app.subspace.core.RecurrenceEngine
import app.subspace.core.ServicePreset
import app.subspace.core.SubscriptionListQuery
import app.subspace.core.SubscriptionRecord
import app.subspace.core.SubscriptionScope
import app.subspace.core.SubscriptionSort
import app.subspace.core.SubscriptionStatus
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset

// ---------------------------------------------------------------- list

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SubscriptionsScreen(state: UiState, model: AppModel, actions: Actions) {
    var query by remember { mutableStateOf(SubscriptionListQuery()) }
    val rows = remember(query, state.records, state.rates, state.currency) { query.apply(state.records, state.currency, state.rates) }
    val nextDates = remember(state.records) {
        val engine = RecurrenceEngine(); val today = LocalDate.now()
        state.records.associate { it.id to engine.nextPayment(it, today)?.date }
    }
    if (state.records.isEmpty()) {
        Column(Modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            EmptyState("Everything recurring, together", "Search ${ServicePreset.all.size} familiar services or create your own. Enter the price you pay; we’ll take care of the schedule.", actions::add)
            Box(Modifier.testTag("subscriptionsBottom")) { PrivacyFootnote() }
        }
        return
    }
    LazyColumn(
        Modifier.fillMaxSize().testTag("subscriptionsList"),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        item(key = "search") {
            OutlinedTextField(
                value = query.search, onValueChange = { query = query.copy(search = it) }, singleLine = true,
                placeholder = { Text("Search services and notes") }, leadingIcon = { Icon(Icons.Rounded.Search, null) },
                trailingIcon = { if (query.search.isNotEmpty()) IconButton(onClick = { query = query.copy(search = "") }) { Icon(Icons.Rounded.Close, "Clear search") } },
                shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth().testTag("search"),
            )
        }
        item(key = "filters") { FilterBar(query) { query = it } }
        item(key = "count") {
            Text("${rows.size} subscriptions", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 8.dp, start = 4.dp))
        }
        items(rows, key = { it.id }, contentType = { "row" }) { record ->
            var menu by remember { mutableStateOf(false) }
            Box(Modifier.animateItem()) {
                Box(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.surfaceContainer)
                        .combinedClickable(onClick = { actions.open(record) }, onLongClick = { menu = true }, onLongClickLabel = "More actions")
                        .padding(horizontal = 14.dp, vertical = 4.dp).testTag("row-${record.name}"),
                ) { SubscriptionRow(record, nextDates[record.id]) }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text("Edit") }, leadingIcon = { Icon(Icons.Rounded.Edit, null) }, onClick = { menu = false; actions.edit(record) })
                    DropdownMenuItem(text = { Text(if (record.archived) "Restore" else "Archive") }, leadingIcon = { Icon(if (record.archived) Icons.Rounded.Unarchive else Icons.Rounded.Archive, null) },
                        onClick = { menu = false; model.save(record.copy(archived = !record.archived))?.let(model::showError) })
                    val active = record.status == SubscriptionStatus.ACTIVE
                    DropdownMenuItem(text = { Text(if (active) "Pause tracking" else "Resume tracking") }, leadingIcon = { Icon(if (active) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, null) },
                        onClick = { menu = false; model.save(record.copy(status = if (active) SubscriptionStatus.PAUSED else SubscriptionStatus.ACTIVE))?.let(model::showError) })
                }
            }
        }
        if (rows.isEmpty()) item(key = "noMatch") {
            Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("No matching subscriptions", style = MaterialTheme.typography.titleMedium)
                Text("Try a different search, category, or status.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                TextButton(onClick = { query = SubscriptionListQuery() }) { Text("Clear filters") }
            }
        }
        item(key = "footer") {
            Text("Amounts stay in their billing currency. Payment amount sorting converts each charge to ${state.currency}; unavailable conversions appear last. Long-press a subscription for more actions.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 12.dp, start = 4.dp).testTag("subscriptionsBottom"))
        }
    }
}

@Composable
private fun FilterBar(query: SubscriptionListQuery, onChange: (SubscriptionListQuery) -> Unit) {
    var filterMenu by remember { mutableStateOf(false) }
    var sortMenu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box {
            FilterChip(selected = query.category != null || query.scope != SubscriptionScope.ALL, onClick = { filterMenu = true },
                label = { Text(query.category?.label ?: query.scope.label) }, leadingIcon = { Icon(Icons.Rounded.FilterList, null, Modifier.size(18.dp)) })
            DropdownMenu(expanded = filterMenu, onDismissRequest = { filterMenu = false }) {
                SubscriptionScope.entries.forEach { scope ->
                    DropdownMenuItem(text = { Text(scope.label + if (query.scope == scope) "  ✓" else "") }, onClick = { onChange(query.copy(scope = scope)); filterMenu = false })
                }
                HorizontalDivider()
                DropdownMenuItem(text = { Text("All categories" + if (query.category == null) "  ✓" else "") }, onClick = { onChange(query.copy(category = null)); filterMenu = false })
                Category.entries.forEach { category ->
                    DropdownMenuItem(text = { Text(category.label + if (query.category == category) "  ✓" else "") }, onClick = { onChange(query.copy(category = category)); filterMenu = false })
                }
            }
        }
        Box {
            FilterChip(selected = false, onClick = { sortMenu = true }, label = { Text(query.sort.label) }, leadingIcon = { Icon(Icons.Rounded.SwapVert, null, Modifier.size(18.dp)) })
            DropdownMenu(expanded = sortMenu, onDismissRequest = { sortMenu = false }) {
                SubscriptionSort.entries.forEach { sort ->
                    DropdownMenuItem(text = { Text(sort.label + if (query.sort == sort) "  ✓" else "") }, onClick = { onChange(query.copy(sort = sort)); sortMenu = false })
                }
            }
        }
    }
}

// ---------------------------------------------------------------- full-screen dialog scaffold

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FullScreen(title: String, onDismiss: () -> Unit, dismissLabel: String = "Close", actions: @Composable () -> Unit = {}, content: @Composable (PaddingValues) -> Unit) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Scaffold(
            containerColor = MaterialTheme.colorScheme.background,
            topBar = {
                TopAppBar(
                    title = { Text(title, fontWeight = FontWeight.SemiBold) },
                    navigationIcon = { IconButton(onClick = onDismiss) { Icon(Icons.Rounded.Close, dismissLabel) } },
                    actions = { actions() },
                )
            },
            content = content,
        )
    }
}

// ---------------------------------------------------------------- preset picker

@Composable
fun PresetPicker(state: UiState, onDismiss: () -> Unit, onPick: (SubscriptionRecord) -> Unit) {
    var search by rememberSaveable { mutableStateOf("") }
    var category by remember { mutableStateOf<Category?>(null) }
    val presets = remember(search, category) { ServicePreset.all.filter { (category == null || it.category == category) && (search.isEmpty() || it.name.contains(search, ignoreCase = true)) } }
    fun create(preset: ServicePreset?) = onPick(SubscriptionRecord(
        name = preset?.name ?: "", symbol = preset?.category?.symbol ?: "creditcard.fill", currency = state.currency,
        category = preset?.category ?: Category.OTHER, reminderDays = state.defaultReminder,
    ))
    FullScreen("Find your service", onDismiss) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding).imePadding(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            item(key = "search") {
                OutlinedTextField(search, { search = it }, singleLine = true, placeholder = { Text("Netflix, ChatGPT, Spotify…") }, leadingIcon = { Icon(Icons.Rounded.Search, null) },
                    shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth().testTag("presetSearch"))
            }
            item(key = "custom") {
                ListItem(headlineContent = { Text("Create custom subscription", fontWeight = FontWeight.SemiBold) }, leadingContent = { Icon(Icons.Rounded.Add, null, tint = MaterialTheme.colorScheme.primary) },
                    colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
                    modifier = Modifier.clip(RoundedCornerShape(16.dp)).clickable { create(null) }.testTag("createCustom"))
            }
            item(key = "categories") {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    item { FilterChip(category == null, { category = null }, { Text("All") }) }
                    items(Category.entries, key = { it.name }) { c -> FilterChip(category == c, { category = if (category == c) null else c }, { Text(c.label) }) }
                }
            }
            item(key = "count") { Text("${presets.size} services", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 8.dp)) }
            items(presets, key = { it.name }, contentType = { "preset" }) { preset ->
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).clickable { create(preset) }.padding(vertical = 6.dp, horizontal = 4.dp).testTag("preset-${preset.name}"),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    BrandIcon(preset.name, preset.category.symbol)
                    Column(Modifier.weight(1f)) {
                        Text(preset.name)
                        Text(preset.category.label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Icon(Icons.Rounded.Add, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (presets.isEmpty()) item { Text("No results for “$search”.", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(16.dp)) }
            item { Text("Service names identify your subscriptions. Logos are trademarks of their owners, shown only to identify each service (logo artwork from Simple Icons, CC0). Enter your actual price; plans and pricing vary.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 12.dp)) }
        }
    }
}

// ---------------------------------------------------------------- editor

private val zone: ZoneId get() = ZoneId.systemDefault()
private fun Instant.day(): LocalDate = atZone(zone).toLocalDate()
/** Keeps the original time of day (as iOS does) and only changes the calendar day. */
private fun Instant.withDay(day: LocalDate): Instant = atZone(zone).toLocalTime().atDate(day).atZone(zone).toInstant()

@Composable
fun SubscriptionEditor(initial: SubscriptionRecord, isNew: Boolean, state: UiState, model: AppModel, onDismiss: () -> Unit, onSaved: () -> Unit) {
    var record by remember { mutableStateOf(initial) }
    var amountText by remember { mutableStateOf(if (initial.amount.signum() > 0) Money.editingText(initial.amount) else "") }
    var intervalChoice by remember { mutableIntStateOf(BillingInterval.STANDARD.indexOf(initial.interval).takeIf { it >= 0 } ?: 6) }
    var customCount by remember { mutableIntStateOf(initial.interval.count) }
    var customUnit by remember { mutableStateOf(initial.interval.unit) }
    var hasTrial by remember { mutableStateOf(initial.trialEnd != null) }
    var hasEnd by remember { mutableStateOf(initial.endDate != null) }
    var reminders by remember { mutableStateOf(initial.reminderDays != null) }
    var validation by remember { mutableStateOf<String?>(null) }
    var currencyPicker by remember { mutableStateOf(false) }

    fun save() {
        val amount = Money.parse(amountText) ?: run { validation = "Enter a valid payment amount."; return }
        val result = record.copy(
            amount = amount, name = record.name.trim(),
            interval = if (intervalChoice == 6) BillingInterval(customCount, customUnit) else BillingInterval.STANDARD[intervalChoice],
            trialEnd = if (hasTrial) record.trialEnd ?: record.nextRenewal else null,
            endDate = if (hasEnd) record.endDate ?: record.nextRenewal else null,
            reminderDays = if (reminders) record.reminderDays ?: state.defaultReminder else null,
        )
        validation = model.save(result)
        if (validation == null) onSaved()
    }

    FullScreen(if (isNew) "New subscription" else "Edit subscription", onDismiss, dismissLabel = "Cancel",
        actions = { TextButton(onClick = ::save, modifier = Modifier.testTag("saveSubscription")) { Text("Save", fontWeight = FontWeight.Bold) } }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).imePadding().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            // Shown at the top, next to the Save button, so the message is visible without scrolling.
            validation?.let {
                Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.error.copy(alpha = 0.10f)).padding(14.dp).testTag("validation"))
            }
            FormSection("Service") {
                OutlinedTextField(record.name, { record = record.copy(name = it) }, label = { Text("Service name") }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("serviceName"))
                Text("Icon", style = MaterialTheme.typography.labelLarge)
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(SymbolChoices, key = { it.first }) { (symbol, icon) ->
                        val selected = record.symbol == symbol
                        Box(Modifier.size(44.dp).clip(RoundedCornerShape(12.dp)).background(if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.25f) else MaterialTheme.colorScheme.surfaceContainerHigh)
                            .clickable { record = record.copy(symbol = symbol) }, contentAlignment = Alignment.Center) {
                            Icon(icon, symbol, tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                ChoiceRow("Category", record.category.label, Category.entries.map { it.label }) { record = record.copy(category = Category.entries[it]) }
            }
            FormSection("Payment", "Enter the total you actually pay each billing period, including taxes. No preset prices are assumed.") {
                OutlinedTextField(amountText, { amountText = it }, label = { Text("Payment amount") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), modifier = Modifier.fillMaxWidth().testTag("paymentAmount"))
                SettingRow("Billing currency", "${record.currency} · ${Currencies.name(record.currency)}") { currencyPicker = true }
                ChoiceRow("Billing frequency", if (intervalChoice == 6) "Custom interval" else BillingInterval.STANDARD[intervalChoice].label,
                    BillingInterval.STANDARD.map { it.label } + "Custom interval") { intervalChoice = it }
                if (intervalChoice == 6) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Every $customCount", modifier = Modifier.weight(1f))
                        OutlinedButton(onClick = { if (customCount > 1) customCount-- }) { Text("−") }
                        OutlinedButton(onClick = { if (customCount < 1000) customCount++ }) { Text("+") }
                    }
                    ChoiceRow("Unit", customUnit.label.replaceFirstChar { it.uppercase() }, BillingUnit.entries.map { it.label.replaceFirstChar { c -> c.uppercase() } }) { customUnit = BillingUnit.entries[it] }
                }
            }
            FormSection("Schedule", "Use a known payment date as the renewal anchor. Past and future dates are calculated from this anchor, starting on your start date. For a trial, set the renewal anchor to the first paid charge. Month-end dates are clamped without shifting later renewals.") {
                DateRow("Started", record.startDate.day()) { record = record.copy(startDate = record.startDate.withDay(it)) }
                DateRow("Renewal anchor", record.nextRenewal.day()) { record = record.copy(nextRenewal = record.nextRenewal.withDay(it)) }
                SwitchRow("Trial", hasTrial) { hasTrial = it }
                if (hasTrial) DateRow("Trial ends", (record.trialEnd ?: record.nextRenewal).day()) { record = record.copy(trialEnd = (record.trialEnd ?: record.nextRenewal).withDay(it)) }
                SwitchRow("End date", hasEnd) { hasEnd = it }
                if (hasEnd) DateRow("Last eligible charge date", (record.endDate ?: record.nextRenewal).day()) { record = record.copy(endDate = (record.endDate ?: record.nextRenewal).withDay(it)) }
            }
            FormSection("Status & reminders") {
                ChoiceRow("Status", record.status.label, SubscriptionStatus.entries.map { it.label }) { record = record.copy(status = SubscriptionStatus.entries[it]) }
                SwitchRow("Renewal reminder", reminders) { reminders = it }
                if (reminders) {
                    val options = listOf(1, 3, 7, 14)
                    ChoiceRow("Notify before", "${record.reminderDays ?: state.defaultReminder} days", options.map { "$it days" }) { record = record.copy(reminderDays = options[it]) }
                    if (!state.remindersEnabled) Text("Turn on renewal reminders in Settings to receive them.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            FormSection("Notes") {
                OutlinedTextField(record.notes, { record = record.copy(notes = it) }, minLines = 3, modifier = Modifier.fillMaxWidth(), label = { Text("Notes") })
            }
            Spacer(Modifier.height(24.dp))
        }
    }
    if (currencyPicker) CurrencyPicker("Billing currency", record.currency, onDismiss = { currencyPicker = false }) { record = record.copy(currency = it); currencyPicker = false }
}

@Composable
fun FormSection(title: String, footer: String? = null, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title.uppercase(), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 4.dp))
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(MaterialTheme.colorScheme.surfaceContainer).padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)) { content() }
        if (footer != null) Text(footer, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 4.dp))
    }
}

@Composable
fun SettingRow(title: String, value: String? = null, icon: ImageVector? = null, onClick: (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        if (icon != null) Icon(icon, null, tint = if (onClick != null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
        Text(title, modifier = Modifier.weight(1f), color = if (onClick != null && value == null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface)
        if (value != null) Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
    }
}

@Composable
fun ChoiceRow(title: String, value: String, options: List<String>, onSelect: (Int) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        SettingRow(title, value) { open = true }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            options.forEachIndexed { index, option -> DropdownMenuItem(text = { Text(option + if (option == value) "  ✓" else "") }, onClick = { onSelect(index); open = false }) }
        }
    }
}

@Composable
fun SwitchRow(title: String, checked: Boolean, modifier: Modifier = Modifier, onChange: (Boolean) -> Unit) {
    Row(modifier.fillMaxWidth().clickable { onChange(!checked) }.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DateRow(title: String, day: LocalDate, onPick: (LocalDate) -> Unit) {
    var open by remember { mutableStateOf(false) }
    SettingRow(title, day.format(MediumDate)) { open = true }
    if (open) {
        // The Material date picker works in UTC midnights.
        val picker = rememberDatePickerState(initialSelectedDateMillis = day.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(
            onDismissRequest = { open = false },
            confirmButton = { TextButton(onClick = { picker.selectedDateMillis?.let { onPick(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()) }; open = false }) { Text("OK") } },
            dismissButton = { TextButton(onClick = { open = false }) { Text("Cancel") } },
        ) { DatePicker(state = picker) }
    }
}

@Composable
fun CurrencyPicker(title: String, selected: String, onDismiss: () -> Unit, onPick: (String) -> Unit) {
    var search by remember { mutableStateOf("") }
    val all = remember { Currencies.common + Currencies.others }
    val shown = remember(search) { if (search.isBlank()) all else all.filter { it.contains(search, true) || Currencies.name(it).contains(search, true) } }
    FullScreen(title, onDismiss) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding).imePadding(), contentPadding = PaddingValues(16.dp)) {
            item { OutlinedTextField(search, { search = it }, singleLine = true, placeholder = { Text("Search currencies") }, leadingIcon = { Icon(Icons.Rounded.Search, null) }, modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp)) }
            items(shown, key = { it }) { code ->
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable { onPick(code) }.padding(vertical = 12.dp, horizontal = 8.dp)) {
                    Text("$code · ${Currencies.name(code)}", modifier = Modifier.weight(1f), fontWeight = if (code == selected) FontWeight.Bold else FontWeight.Normal)
                    if (code == selected) Text("✓", color = MaterialTheme.colorScheme.primary)
                }
            }
        }
    }
}

// ---------------------------------------------------------------- detail

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SubscriptionDetail(record: SubscriptionRecord, state: UiState, model: AppModel, actions: Actions) {
    var deleting by remember { mutableStateOf(false) }
    val next = remember(record) { RecurrenceEngine().nextPayment(record) }
    ModalBottomSheet(onDismissRequest = actions::close, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = MaterialTheme.colorScheme.surfaceContainerLow) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ServiceIcon(record, size = 60)
                Text(record.name, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Text(Money.format(record.amount, record.currency), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold)
                Text(record.interval.label, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            FormSection("At a glance") {
                SettingRow("Category", record.category.label)
                SettingRow("Status", if (record.archived) "Archived" else record.status.label)
                SettingRow("Started", record.startDay().format(MediumDate))
                next?.let { SettingRow("Next payment", it.date.format(MediumDate)) }
                record.trialEndDay()?.let { SettingRow("Trial ends", it.format(MediumDate)) }
                record.endDay()?.let { SettingRow("Ends", it.format(MediumDate)) }
                val converted = state.converted(record)
                if (converted != null) {
                    val annual = converted.multiply(record.interval.periodsPerYear, Money.MATH)
                    SettingRow("Monthly average", Money.format(annual.divide(java.math.BigDecimal(12), Money.MATH), state.currency))
                    SettingRow("Annual average", Money.format(annual, state.currency))
                } else Text("Exchange rate unavailable for this currency.", color = ChartColors.warning)
                SettingRow("Reminder", record.reminderDays?.let { "$it days before" } ?: "Off")
            }
            if (record.notes.isNotEmpty()) FormSection("Notes") { Text(record.notes) }
            FormSection("Actions", "Paused, canceled, and archived subscriptions are excluded from totals, payment forecasts, and reminders. Archive keeps the record for later restoration.") {
                SettingRow("Edit subscription", icon = Icons.Rounded.Edit) { actions.edit(record) }
                SettingRow(if (record.archived) "Restore subscription" else "Archive subscription", icon = if (record.archived) Icons.Rounded.Unarchive else Icons.Rounded.Archive) {
                    model.save(record.copy(archived = !record.archived))?.let(model::showError)
                }
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable { deleting = true }.padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(Icons.Rounded.Delete, null, tint = MaterialTheme.colorScheme.error); Text("Delete permanently", color = MaterialTheme.colorScheme.error)
                }
            }
            Button(onClick = actions::close, modifier = Modifier.fillMaxWidth()) { Text("Done") }
        }
    }
    if (deleting) AlertDialog(
        onDismissRequest = { deleting = false },
        title = { Text("Delete ${record.name}?") }, text = { Text("This cannot be undone.") },
        confirmButton = { TextButton(onClick = { deleting = false; model.delete(record); actions.close() }) { Text("Delete subscription", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = { deleting = false }) { Text("Cancel") } },
    )
}

