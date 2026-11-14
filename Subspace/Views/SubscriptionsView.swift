import SwiftUI
import SubspaceCore

struct SubscriptionsView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""
    @State private var filter = "All"
    @State private var category: SubspaceCore.Category?
    @State private var selected: SubscriptionRecord?
    private var filtered: [SubscriptionRecord] {
        store.records.filter {
            (filter == "Archived" ? $0.archived : !$0.archived) &&
            (filter == "All" || filter == "Archived" || $0.status.rawValue.capitalized == filter) &&
            (category == nil || $0.category == category) &&
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.notes.localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Status", selection: $filter) { ForEach(["All", "Active", "Paused", "Canceled", "Archived"], id: \.self) { Text($0).tag($0) } }
                    Picker("Category", selection: $category) {
                        Text("All categories").tag(nil as SubspaceCore.Category?)
                        ForEach(SubspaceCore.Category.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                    }
                }.listRowBackground(Color.primary.opacity(0.04))
                Section("\(filtered.count) subscriptions") {
                    ForEach(filtered) { record in
                        Button { selected = record } label: { SubscriptionRow(record: record) }.buttonStyle(.plain)
                            .swipeActions {
                                Button(record.archived ? "Restore" : "Archive", systemImage: record.archived ? "arrow.uturn.backward" : "archivebox") {
                                    var updated = record; updated.archived.toggle()
                                    do { try store.save(updated) } catch { store.error = error.localizedDescription }
                                }.tint(.purple)
                            }
                    }
                }.listRowBackground(Color.primary.opacity(0.04))
                if filtered.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "No subscriptions here" : "No matches", systemImage: "rectangle.stack", description: Text(search.isEmpty ? "Use Add subscription to start tracking, or change your filters." : "Try another service name or note."))
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden).background { SpaceBackground() }
            .searchable(text: $search, prompt: "Search services and notes")
            .navigationTitle("Subscriptions")
            .sheet(item: $selected) { SubscriptionDetail(record: $0) }
        }
    }
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
                    Button { create(nil) } label: { Label("Create custom subscription", systemImage: "plus.circle.fill").font(.headline).padding(.vertical, 8) }
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
                    TextField("Service name", text: $record.name).textContentType(.organizationName)
                    Picker("Icon", selection: $record.symbol) { ForEach(symbols, id: \.self) { Image(systemName: $0).tag($0) } }
                    Picker("Category", selection: $record.category) { ForEach(SubspaceCore.Category.allCases, id: \.self) { Label($0.rawValue, systemImage: $0.symbol).tag($0) } }
                }
                Section {
                    TextField("Payment amount", text: $amountText).keyboardType(.decimalPad)
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
                ToolbarItem(placement: .confirmationAction) { Button("Save", systemImage: "checkmark", action: save).fontWeight(.semibold).disabled(saved) }
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
