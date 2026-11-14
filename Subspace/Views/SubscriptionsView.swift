import SwiftUI
import SubspaceCore

struct SubscriptionsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = SubscriptionListQuery()
    @State private var selected: SubscriptionRecord?
    @State private var editing: SubscriptionRecord?
    private var filtered: [SubscriptionRecord] { query.apply(to: store.records, reportingCurrency: store.currency, rates: store.rates) }
    var body: some View {
        NavigationStack {
            Group {
                if store.records.isEmpty {
                    ScrollView {
                        VStack(spacing: 20) {
                            SubscriptionEmptyState(title: "Everything recurring, together", message: "Search 147 familiar services or create your own. Enter the price you pay; we’ll take care of the schedule.", symbol: "rectangle.stack")
                            PrivacyFootnote().accessibilityIdentifier("subscriptionsBottom")
                        }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
                    }
                } else { subscriptionList }
            }
            .background { SpaceBackground() }.navigationTitle("Subscriptions")
            .subscriptionToolbar()
            .sheet(item: $selected) { SubscriptionDetail(record: $0) }
            .sheet(item: $editing) { SubscriptionEditor(record: $0) }
        }
    }
    private var subscriptionList: some View {
        let rows = filtered
        return List {
            Section {
                ViewThatFits(in: .horizontal) {
                    HStack { filterMenu; Spacer(); sortMenu }
                    VStack(alignment: .leading, spacing: 12) { filterMenu; sortMenu }
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            Section("\(rows.count) subscriptions") {
                ForEach(rows) { record in
                    Button { selected = record } label: { SubscriptionRow(record: record) }.buttonStyle(.plain)
                        .accessibilityIdentifier("subscriptionRow-" + record.name)
                        .swipeActions(edge: .leading) { Button("Edit", systemImage: "pencil") { editing = record }.tint(.purple) }
                        .swipeActions { Button(record.archived ? "Restore" : "Archive", systemImage: record.archived ? "arrow.uturn.backward" : "archivebox") { archive(record) }.tint(.purple) }
                        .contextMenu {
                            Button("View details", systemImage: "info.circle") { selected = record }
                            Button("Edit", systemImage: "pencil") { editing = record }
                            Button(record.archived ? "Restore" : "Archive", systemImage: "archivebox") { archive(record) }
                            Button(record.status == .active ? "Pause tracking" : "Resume tracking", systemImage: record.status == .active ? "pause" : "play") {
                                var updated = record; updated.status = record.status == .active ? .paused : .active
                                save(updated)
                            }
                        }
                }
                if rows.isEmpty {
                    ContentUnavailableView("No matching subscriptions", systemImage: "line.3.horizontal.decrease", description: Text("Try a different search, category, or status."))
                    Button("Clear filters") { query = SubscriptionListQuery() }
                }
            }
            Section { Text("Amounts stay in their billing currency. Payment amount sorting converts each charge to \(store.currency); unavailable conversions appear last.").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("subscriptionsBottom") }
        }
        .scrollContentBackground(.hidden).scrollEdgeEffectStyle(.hard, for: .bottom)
        .searchable(text: $query.search, prompt: "Search services and notes")
        .scrollDismissesKeyboard(.interactively)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: rows.map(\.id))
    }
    private var filterMenu: some View {
        Menu {
            Picker("Status", selection: $query.scope) { ForEach(SubscriptionScope.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Picker("Category", selection: $query.category) {
                Text("All categories").tag(nil as SubspaceCore.Category?)
                ForEach(SubspaceCore.Category.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
            }
            if query.category != nil || query.scope != .all { Button("Reset filters") { query.category = nil; query.scope = .all } }
        } label: { Label(query.category?.rawValue ?? query.scope.rawValue, systemImage: "line.3.horizontal.decrease") }
        .buttonStyle(.glass).accessibilityLabel("Filter subscriptions").accessibilityIdentifier("subscriptionFilters")
    }
    private var sortMenu: some View {
        Menu { Picker("Sort", selection: $query.sort) { ForEach(SubscriptionSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } } }
        label: { Label(query.sort.rawValue, systemImage: "arrow.up.arrow.down") }
            .buttonStyle(.glass).accessibilityLabel("Sort subscriptions").accessibilityIdentifier("subscriptionSort")
    }
    private func archive(_ record: SubscriptionRecord) { var updated = record; updated.archived.toggle(); save(updated) }
    private func save(_ record: SubscriptionRecord) { do { try store.save(record) } catch { store.error = error.localizedDescription } }
}

struct PresetPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var category: SubspaceCore.Category?
    @State private var draft: SubscriptionRecord?
    private var presets: [ServicePreset] { ServicePreset.all.filter { (category == nil || $0.category == category) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { create(nil) } label: { Label("Create custom subscription", systemImage: "plus.circle.fill").font(.headline).padding(.vertical, 8) }.accessibilityIdentifier("createCustomSubscription")
                    Picker("Category", selection: $category) {
                        Text("All categories").tag(nil as SubspaceCore.Category?)
                        ForEach(SubspaceCore.Category.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                    }
                }
                Section {
                    ForEach(presets) { preset in
                        Button { create(preset) } label: {
                            HStack(spacing: 14) {
                                Text(preset.initials).font(.subheadline.bold()).foregroundStyle(Color.spaceAccent).frame(width: 44, height: 44).background(Color.spaceAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                                VStack(alignment: .leading, spacing: 4) { Text(preset.name).foregroundStyle(.primary); Text(preset.category.rawValue).font(.caption).foregroundStyle(.secondary) }
                                Spacer(); Image(systemName: "plus").foregroundStyle(.secondary)
                            }.padding(.vertical, 3)
                        }
                    }
                    if presets.isEmpty { ContentUnavailableView.search(text: search) }
                } header: { Text("\(presets.count) services") } footer: { Text("Service names identify your subscriptions. Icons are original monograms or Apple SF Symbols, not official logos. Enter your actual price; plans and pricing vary.") }
            }
            .searchable(text: $search, prompt: "Netflix, ChatGPT, Spotify…")
            .navigationTitle("Find your service").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } } }
            .sheet(item: $draft) { record in SubscriptionEditor(record: record) { dismiss() } }
        }
    }
    private func create(_ preset: ServicePreset?) {
        draft = SubscriptionRecord(name: preset?.name ?? "", symbol: preset?.symbol ?? "creditcard.fill", currency: store.currency, category: preset?.category ?? .other, reminderDays: store.defaultReminder)
    }
}

struct SubscriptionEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var record: SubscriptionRecord
    @State private var amountText = ""
    @State private var intervalChoice = 2
    @State private var customCount = 1
    @State private var customUnit = BillingUnit.month
    @State private var hasTrial = false
    @State private var hasEnd = false
    @State private var reminders = true
    @State private var validation: String?
    @State private var saved = false
    var onSave: () -> Void = {}
    private let symbols = ["creditcard.fill", "play.tv.fill", "music.note", "sparkles", "gamecontroller.fill", "lock.shield.fill", "cloud.fill", "figure.run", "graduationcap.fill", "newspaper.fill", "server.rack", "curlybraces", "heart.fill", "globe", "checkmark.seal.fill", "square.grid.2x2.fill"]
    var body: some View {
        NavigationStack {
            Form {
                Section("Service") {
                    TextField("Service name", text: $record.name).textContentType(.organizationName).accessibilityIdentifier("serviceName")
                    Picker("Icon", selection: $record.symbol) { ForEach(symbols, id: \.self) { Image(systemName: $0).tag($0) } }
                    Picker("Category", selection: $record.category) { ForEach(SubspaceCore.Category.allCases, id: \.self) { Label($0.rawValue, systemImage: $0.symbol).tag($0) } }
                }
                Section {
                    TextField("Payment amount", text: $amountText).keyboardType(.decimalPad).accessibilityIdentifier("paymentAmount")
                    CurrencyPicker(selection: $record.currency, title: "Billing currency")
                    Picker("Billing frequency", selection: $intervalChoice) {
                        ForEach(Array(BillingInterval.standard.enumerated()), id: \.offset) { index, interval in Text(interval.label).tag(index) }
                        Text("Custom interval").tag(6)
                    }
                    if intervalChoice == 6 {
                        Stepper("Every \(customCount)", value: $customCount, in: 1...1000)
                        Picker("Unit", selection: $customUnit) { ForEach(BillingUnit.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                    }
                } header: { Text("Payment") } footer: { Text("Enter the total you actually pay each billing period, including taxes. No preset prices are assumed.") }
                Section {
                    DatePicker("Started", selection: $record.startDate, displayedComponents: .date)
                    DatePicker("Renewal anchor", selection: $record.nextRenewal, displayedComponents: .date)
                    Toggle("Trial", isOn: $hasTrial)
                    if hasTrial { DatePicker("Trial ends", selection: Binding(get: { record.trialEnd ?? record.nextRenewal }, set: { record.trialEnd = $0 }), displayedComponents: .date) }
                    Toggle("End date", isOn: $hasEnd)
                    if hasEnd { DatePicker("Last eligible charge date", selection: Binding(get: { record.endDate ?? record.nextRenewal }, set: { record.endDate = $0 }), displayedComponents: .date) }
                } header: { Text("Schedule") } footer: { Text("Use a known payment date as the renewal anchor. Past and future dates are calculated from this anchor, starting on your start date. For a trial, set the renewal anchor to the first paid charge; no scheduled charges occur before the trial ends. Month-end dates are clamped without shifting subsequent renewals.") }
                Section("Status & reminders") {
                    Picker("Status", selection: $record.status) { ForEach(SubscriptionStatus.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                    Toggle("Renewal reminder", isOn: $reminders)
                    if reminders {
                        Picker("Notify before", selection: Binding(get: { record.reminderDays ?? store.defaultReminder }, set: { record.reminderDays = $0 })) { ForEach([1,3,7,14], id: \.self) { Text("\($0) days").tag($0) } }
                        if !store.remindersEnabled { Text("Enable notifications in Settings to receive reminders.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Section("Notes") { TextEditor(text: $record.notes).frame(minHeight: 90).accessibilityLabel("Subscription notes") }
                if let validation { Section { Text(validation).foregroundStyle(.red).accessibilityLabel("Validation error: \(validation)") } }
            }
            .navigationTitle(store.records.contains(where: { $0.id == record.id }) ? "Edit subscription" : "New subscription").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", systemImage: "checkmark", action: save).fontWeight(.semibold).disabled(saved).accessibilityIdentifier("saveSubscription") }
            }
            .onAppear {
                if record.amount > 0 { amountText = NSDecimalNumber(decimal: record.amount).description(withLocale: Locale.current) }
                intervalChoice = BillingInterval.standard.firstIndex(of: record.interval) ?? 6
                customCount = record.interval.count; customUnit = record.interval.unit
                hasTrial = record.trialEnd != nil; hasEnd = record.endDate != nil; reminders = record.reminderDays != nil
            }
            .sensoryFeedback(.success, trigger: saved)
        }
    }
    private func save() {
        // Decimal(string:locale:) avoids converting financial input through binary floating point.
        guard let amount = Money.parse(amountText) else { validation = "Enter a valid payment amount."; return }
        record.amount = amount
        record.name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
        record.interval = intervalChoice == 6 ? BillingInterval(count: customCount, unit: customUnit) : BillingInterval.standard[intervalChoice]
        record.trialEnd = hasTrial ? (record.trialEnd ?? record.nextRenewal) : nil
        record.endDate = hasEnd ? (record.endDate ?? record.nextRenewal) : nil
        record.reminderDays = reminders ? (record.reminderDays ?? store.defaultReminder) : nil
        do { try store.save(record); saved = true; dismiss(); onSave() }
        catch { validation = error.localizedDescription }
    }
}
struct CurrencyPicker: View {
    @Binding var selection: String
    var title = "Currency"
    private let common = ["CAD", "USD", "EUR", "GBP", "AUD", "JPY", "CHF", "NZD", "CNY", "INR", "KRW", "BRL", "MXN", "SGD", "HKD", "SEK", "NOK", "DKK", "PLN", "CZK", "ZAR"]
    var body: some View {
        Picker(title, selection: $selection) {
            Section("Common") { ForEach(common, id: \.self) { Text("\($0) · \(Locale.current.localizedString(forCurrencyCode: $0) ?? $0)").tag($0) } }
            Section("Other ISO currencies") { ForEach(Locale.commonISOCurrencyCodes.filter { !common.contains($0) }.sorted(), id: \.self) { Text("\($0) · \(Locale.current.localizedString(forCurrencyCode: $0) ?? $0)").tag($0) } }
        }
    }
}

struct SubscriptionDetail: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let record: SubscriptionRecord
    @State private var editing = false
    @State private var deleting = false
    private var current: SubscriptionRecord { store.records.first { $0.id == record.id } ?? record }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 14) {
                        ServiceIcon(record: current).scaleEffect(1.3).padding(10)
                        Text(current.name).font(.title.bold())
                        Text(Money.format(current.amount, currency: current.currency)).font(.largeTitle.weight(.semibold))
                        Text(current.interval.label).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 20)
                }
                Section("At a glance") {
                    LabeledContent("Category", value: current.category.rawValue)
                    LabeledContent("Status", value: current.archived ? "Archived" : current.status.rawValue.capitalized)
                    LabeledContent("Started", value: current.startDate.formatted(date: .abbreviated, time: .omitted))
                    if let next = RecurrenceEngine().nextPayment(current) { LabeledContent("Next payment", value: next.date.formatted(date: .abbreviated, time: .omitted)) }
                    if let trial = current.trialEnd { LabeledContent("Trial ends", value: trial.formatted(date: .abbreviated, time: .omitted)) }
                    if let end = current.endDate { LabeledContent("Ends", value: end.formatted(date: .abbreviated, time: .omitted)) }
                    if let converted = store.converted(current) {
                        LabeledContent("Monthly average", value: store.money(converted * current.interval.periodsPerYear / 12))
                        LabeledContent("Annual average", value: store.money(converted * current.interval.periodsPerYear))
                    } else { Text("Exchange rate unavailable for this currency.").foregroundStyle(.orange) }
                    LabeledContent("Reminder", value: current.reminderDays.map { "\($0) days before" } ?? "Off")
                }
                if !current.notes.isEmpty { Section("Notes") { Text(current.notes).textSelection(.enabled) } }
                Section {
                    Button("Edit subscription", systemImage: "pencil") { editing = true }
                    Button(current.archived ? "Restore subscription" : "Archive subscription", systemImage: current.archived ? "arrow.uturn.backward" : "archivebox") {
                        var value = current; value.archived.toggle()
                        do { try store.save(value) } catch { store.error = error.localizedDescription }
                    }
                    Button("Delete permanently", systemImage: "trash", role: .destructive) { deleting = true }
                } footer: { Text("Paused, canceled, and archived subscriptions are excluded from totals, payment forecasts, and reminders. Archive preserves the record for later restoration.") }
            }
            .navigationTitle("Subscription").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $editing) { SubscriptionEditor(record: current) }
            .confirmationDialog("Permanently delete \(current.name)? This cannot be undone.", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete subscription", role: .destructive) { do { try store.delete(current); dismiss() } catch { store.error = error.localizedDescription } }
            }
        }
    }
}
