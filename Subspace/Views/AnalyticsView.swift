import SwiftUI
import Charts
import SubspaceCore

struct SpendingBucket: Identifiable {
    let date: Date
    let total: Decimal
    let historical: Bool
    var id: Date { date }
    var value: Double { NSDecimalNumber(decimal: total).doubleValue }
}
struct SpendingChart: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var compact = false
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var month = Calendar.current.component(.month, from: .now)
    @State private var monthly = false
    @State private var selection: Date?
    private var calendar: Calendar { .current }
    private var buckets: [SpendingBucket] {
        guard let first = calendar.date(from: DateComponents(year: year, month: monthly ? month : 1, day: 1)) else { return [] }
        let count = monthly ? (calendar.range(of: .day, in: .month, for: first)?.count ?? 0) : 12
        let component: Calendar.Component = monthly ? .day : .month
        return (0..<count).compactMap { index in
            guard let date = calendar.date(byAdding: component, value: index, to: first), let end = calendar.date(byAdding: component, value: 1, to: date) else { return nil }
            return SpendingBucket(date: date, total: store.total(store.payments(in: DateInterval(start: date, end: end))), historical: end <= calendar.startOfDay(for: .now))
        }
    }
    private var selectedBucket: SpendingBucket? {
        guard let selection else { return nil }
        return buckets.first { calendar.isDate($0.date, equalTo: selection, toGranularity: monthly ? .day : .month) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !compact {
                Picker("Chart period", selection: $monthly) { Text("Annual").tag(false); Text("Monthly").tag(true) }.pickerStyle(.segmented)
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.glass).accessibilityLabel("Previous period").disabled(year <= 1900)
                    Spacer()
                    Text(monthly ? "\(calendar.monthSymbols[month - 1]) \(String(year))" : String(year)).font(.headline)
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.glass).accessibilityLabel("Next period").disabled(year >= 2200)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(store.money(selectedBucket?.total ?? buckets.reduce(0) { $0 + $1.total })).font(.title2.bold()).contentTransition(.numericText()).minimumScaleFactor(0.5)
                Spacer()
                Text(selectedBucket.map { $0.date.formatted(monthly ? .dateTime.month(.abbreviated).day() : .dateTime.month(.wide)) } ?? "Scheduled · \(store.currency)").font(.caption).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(buckets) { bucket in
                    BarMark(x: .value("Date", bucket.date, unit: monthly ? .day : .month), y: .value("Scheduled payments", bucket.value))
                        .foregroundStyle(bucket.historical ? Color.spaceBlue : Color.spaceAccent)
                        .cornerRadius(5)
                        .opacity(selection == nil || selectedBucket?.id == bucket.id ? 1 : 0.35)
                        .accessibilityLabel(bucket.date.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue(store.money(bucket.total))
                }
                if !monthly {
                    RuleMark(y: .value("Current monthly average", NSDecimalNumber(decimal: store.summary.monthly).doubleValue))
                        .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
                if let selectedBucket { RuleMark(x: .value("Selection", selectedBucket.date, unit: monthly ? .day : .month)).foregroundStyle(.primary.opacity(0.2)) }
            }
            .chartXSelection(value: $selection)
            .chartXAxis {
                AxisMarks(values: .stride(by: monthly ? .day : .month, count: monthly ? 5 : 1)) { _ in
                    AxisValueLabel(format: monthly ? .dateTime.day() : .dateTime.month(.narrow))
                }
            }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
            .frame(height: compact ? 170 : 235)
            HStack(spacing: 16) {
                legend("Past schedule", color: .spaceBlue)
                legend("Forecast", color: .spaceAccent)
            }
            if !monthly { Text("Dashed line: current normalized monthly average. Bars: scheduled charges in each month.").font(.caption2).foregroundStyle(.secondary) }
            if !compact { Text("Past values are reconstructed from current schedules, not confirmed transactions. Editing a schedule recalculates this history. All amounts converted using the current cached exchange rates.").font(.caption2).foregroundStyle(.secondary) }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.4), value: monthly)
        .onChange(of: monthly) { selection = nil }
    }
    private func legend(_ text: String, color: Color) -> some View { HStack(spacing: 5) { Circle().fill(color).frame(width: 6, height: 6); Text(text).font(.caption2).foregroundStyle(.secondary) } }
    private func shift(_ direction: Int) {
        selection = nil
        if monthly {
            month += direction
            if month == 0 { month = 12; year -= 1 }
            if month == 13 { month = 1; year += 1 }
        } else { year += direction }
    }
}
struct BreakdownItem: Identifiable {
    let name: String
    let amount: Decimal
    var id: String { name }
    var value: Double { NSDecimalNumber(decimal: amount).doubleValue }
}
struct AnalyticsView: View {
    @Environment(AppStore.self) private var store
    @State private var calendarOpen = false
    @State private var selectedAngle: Double?
    @State private var selectedService: String?
    private var active: [SubscriptionRecord] { store.visible.filter { $0.status == .active && ($0.endDate.map { $0 >= Calendar.current.startOfDay(for: .now) } ?? true) } }
    private var categories: [BreakdownItem] {
        SubspaceCore.Category.allCases.compactMap { category in
            let amount = active.filter { $0.category == category }.reduce(Decimal.zero) { $0 + annual($1) }
            return amount > 0 ? BreakdownItem(name: category.rawValue, amount: amount) : nil
        }.sorted { $0.amount > $1.amount }
    }
    private var currencies: [BreakdownItem] {
        Set(active.map(\.currency)).sorted().map { code in BreakdownItem(name: code, amount: active.filter { $0.currency == code }.reduce(0) { $0 + annual($1) }) }.filter { $0.amount > 0 }
    }
    private var services: [BreakdownItem] { active.map { BreakdownItem(name: $0.name + " · " + String($0.id.uuidString.prefix(4)), amount: annual($0)) }.filter { $0.amount > 0 }.sorted { $0.amount > $1.amount } }
    private var selectedCategory: BreakdownItem? {
        guard let selectedAngle else { return nil }
        var running = 0.0
        for item in categories { running += item.value; if selectedAngle <= running { return item } }
        return nil
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    RateNotice()
                    Surface { SpendingChart() }
                    if active.isEmpty {
                        ContentUnavailableView("Room for insight", systemImage: "chart.pie", description: Text("Add an active subscription to explore your spending by service, category, and currency."))
                    } else {
                        SectionTitle(title: "Where it goes", subtitle: "Normalized annual spending by category")
                        Surface {
                            if categories.isEmpty { Text("Exchange rates are needed to show this breakdown.").foregroundStyle(.secondary) }
                            else {
                                Chart(categories) { item in
                                    SectorMark(angle: .value("Annual cost", item.value), innerRadius: .ratio(0.68), angularInset: 3)
                                        .cornerRadius(5).foregroundStyle(by: .value("Category", item.name))
                                        .opacity(selectedCategory == nil || selectedCategory?.id == item.id ? 1 : 0.35)
                                }.chartAngleSelection(value: $selectedAngle).chartLegend(position: .bottom, spacing: 14).frame(height: 270)
                                if let item = selectedCategory { LabeledContent(item.name, value: store.money(item.amount)).font(.subheadline).padding(.top, 12) }
                            }
                        }
                        SectionTitle(title: "By service", subtitle: "Normalized annual cost · tap to inspect")
                        Surface {
                            if services.isEmpty { Text("No converted amounts available.").foregroundStyle(.secondary) }
                            else {
                                Chart(services) { item in
                                    BarMark(x: .value("Annual cost", item.value), y: .value("Service", item.name))
                                        .foregroundStyle(Color.spaceAccent.gradient).cornerRadius(4)
                                        .opacity(selectedService == nil || selectedService == item.name ? 1 : 0.4)
                                }.chartYSelection(value: $selectedService).chartYAxis { AxisMarks { _ in AxisValueLabel().font(.caption2) } }.frame(height: CGFloat(max(services.count, 2)) * 38)
                                if let item = services.first(where: { $0.name == selectedService }) { Text("\(item.name): \(store.money(item.amount)) / year").font(.caption).padding(.top) }
                            }
                        }
                        SectionTitle(title: "Across currencies", subtitle: "Annual costs converted to \(store.currency); billing currencies retained")
                        Surface {
                            VStack(spacing: 18) {
                                ForEach(currencies) { item in
                                    VStack(spacing: 8) {
                                        HStack { Text(item.name).font(.subheadline.weight(.semibold)); Spacer(); Text(store.money(item.amount)).font(.subheadline) }
                                        ProgressView(value: item.value, total: max(currencies.reduce(0) { $0 + $1.value }, 1)).tint(.spaceBlue)
                                    }
                                }
                            }
                        }
                    }
                    Button { calendarOpen = true } label: { Label("Open payment calendar", systemImage: "calendar").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12) }.buttonStyle(.glass)
                }.padding(20)
            }.background { SpaceBackground() }.navigationTitle("Analytics")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Calendar", systemImage: "calendar") { calendarOpen = true } } }
                .fullScreenCover(isPresented: $calendarOpen) { PaymentCalendarView() }
        }
    }
    private func annual(_ record: SubscriptionRecord) -> Decimal { (store.converted(record) ?? 0) * record.interval.periodsPerYear }
}
