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
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var chartHeight = 220.0
    @ScaledMetric(relativeTo: .body) private var compactHeight = 145.0
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
                if typeSize.isAccessibilitySize {
                    periodPicker.pickerStyle(.menu)
                } else { periodPicker.pickerStyle(.segmented) }
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.glass).accessibilityLabel("Previous period").disabled(year <= 1900)
                    Spacer()
                    Text(monthly ? "\(calendar.monthSymbols[month - 1]) \(String(year))" : String(year)).font(.headline)
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.glass).accessibilityLabel("Next period").disabled(year >= 2200)
                }
            }
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { summaryValue; summaryCaption }
            } else {
                HStack(alignment: .firstTextBaseline) { summaryValue; Spacer(); summaryCaption }
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
                if let selectedBucket {
                    RuleMark(x: .value("Selection", selectedBucket.date, unit: monthly ? .day : .month))
                        .foregroundStyle(.primary.opacity(0.25))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .padScale)) {
                            Text(store.money(selectedBucket.total)).font(.caption.weight(.semibold)).padding(8)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                        }
                }
            }
            .chartXSelection(value: $selection)
            .chartGesture { proxy in
                SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: monthly ? .day : .month, count: monthly ? (typeSize.isAccessibilitySize ? 10 : 5) : (typeSize.isAccessibilitySize ? 3 : 1))) { _ in
                    AxisValueLabel(format: monthly ? .dateTime.day() : .dateTime.month(.narrow))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel { if let amount = value.as(Double.self) { Text(amount, format: .number.notation(.compactName)) } }
                }
            }
            .chartYAxisLabel(store.currency)
            .frame(height: compact ? compactHeight : chartHeight)
            .accessibilityIdentifier("spendingChart")
            HStack(spacing: 16) {
                legend("Past estimate", color: .spaceBlue)
                legend("Forecast", color: .spaceAccent)
            }
            if !monthly { Text("Dashed line: current normalized monthly average. Bars: scheduled charges in each month.").font(.caption2).foregroundStyle(.secondary) }
            if !compact { Text("History is estimated from your current schedules, not bank transactions. Amounts use cached exchange rates.").font(.caption2).foregroundStyle(.secondary) }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: monthly)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: year)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: month)
        .onChange(of: monthly) { selection = nil }
    }
    private var summaryValue: some View {
        Text(store.money(selectedBucket?.total ?? buckets.reduce(0) { $0 + $1.total }))
            .font(.title2.bold()).contentTransition(reduceMotion ? .identity : .numericText())
            .fixedSize(horizontal: false, vertical: true)
    }
    private var summaryCaption: some View {
        Text(selectedBucket.map { $0.date.formatted(monthly ? .dateTime.month(.abbreviated).day() : .dateTime.month(.wide)) } ?? "Scheduled · \(store.currency)")
            .font(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier(selectedBucket == nil ? "chartPeriodSummary" : "chartSelectionSummary")
    }
    private var periodPicker: some View {
        Picker("Chart period", selection: $monthly) { Text("Annual").tag(false); Text("Monthly").tag(true) }.accessibilityIdentifier("chartPeriod")
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var donutHeight = 230.0
    @ScaledMetric(relativeTo: .body) private var serviceRowHeight = 36.0
    @State private var calendarOpen = false
    @State private var selectedAngle: Double?
    @State private var selectedService: SubscriptionRecord?
    @State private var serviceSelection: String?
    @State private var explanation = false
    private var active: [SubscriptionRecord] { store.visible.filter { $0.status == .active && ($0.endDate.map { $0 >= Calendar.current.startOfDay(for: .now) } ?? true) } }
    private var categories: [BreakdownItem] {
        let items = SubspaceCore.Category.allCases.compactMap { category -> BreakdownItem? in
            let amount = active.filter { $0.category == category }.reduce(Decimal.zero) { $0 + annual($1) }
            return amount > 0 ? BreakdownItem(name: category.rawValue, amount: amount) : nil
        }.sorted { $0.amount > $1.amount }
        let remaining = items.dropFirst(5).reduce(Decimal.zero) { $0 + $1.amount }
        return Array(items.prefix(5)) + (remaining > 0 ? [BreakdownItem(name: "Other categories", amount: remaining)] : [])
    }
    private var currencies: [BreakdownItem] {
        Set(active.map(\.currency)).sorted().map { code in BreakdownItem(name: code, amount: active.filter { $0.currency == code }.reduce(0) { $0 + annual($1) }) }.filter { $0.amount > 0 }
    }
    private var ranked: [SubscriptionRecord] { active.filter { store.converted($0) != nil }.sorted { annual($0) > annual($1) } }
    private var selectedCategory: BreakdownItem? {
        guard let selectedAngle else { return nil }
        var running = 0.0
        for item in categories { running += item.value; if selectedAngle < running { return item } }
        return nil
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if store.visible.isEmpty {
                        SubscriptionEmptyState(title: "See the bigger picture", message: "Add a subscription to see scheduled payments, average costs, and where your money goes.", symbol: "chart.bar.xaxis")
                    } else {
                        RateNotice()
                        Surface { SpendingChart() }
                        if active.isEmpty {
                            Surface { Text("No active commitments. Payment history remains available for schedules that ended; paused and canceled records are excluded.").font(.subheadline).foregroundStyle(.secondary) }
                        } else {
                            SectionTitle(title: "Where it goes", subtitle: "Normalized annual cost by category")
                            categoryChart
                            SectionTitle(title: "By subscription", subtitle: "Normalized annual cost · \(store.currency)")
                            serviceBreakdown
                            SectionTitle(title: "Across currencies", subtitle: "Converted annual costs by original billing currency")
                            currencyBreakdown
                        }
                        Surface {
                            DisclosureGroup("How these figures work", isExpanded: $explanation) {
                                Text("Bars show scheduled charges. The dashed line shows today’s normalized monthly average. Past payments are estimates reconstructed from current schedules, using cached exchange rates. Editing or archiving a plan recalculates these estimates.")
                                    .font(.caption).foregroundStyle(.secondary).padding(.top, 10)
                            }.animation(reduceMotion ? nil : .smooth(duration: 0.25), value: explanation)
                        }
                    }
                    Button("Payment calendar", systemImage: "calendar") { calendarOpen = true }
                        .buttonStyle(.glass).controlSize(.large).accessibilityIdentifier("analyticsBottom")
                }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: store.visible.isEmpty)
            }
            .accessibilityIdentifier("analyticsScroll").scrollEdgeEffectStyle(.hard, for: .bottom)
            .background { SpaceBackground() }.navigationTitle("Analytics")
            .subscriptionToolbar()
            .fullScreenCover(isPresented: $calendarOpen) { PaymentCalendarView() }
            .sheet(item: $selectedService) { SubscriptionDetail(record: $0) }
        }
    }
    private var categoryChart: some View {
        Surface {
            if categories.isEmpty { Text("Refresh exchange rates to show this breakdown.").foregroundStyle(.secondary) }
            else {
                VStack(alignment: .leading, spacing: 16) {
                    Chart(categories) { item in
                        SectorMark(angle: .value("Annual cost", item.value), innerRadius: .ratio(0.7), angularInset: 3)
                            .cornerRadius(4).foregroundStyle(by: .value("Category", item.name))
                            .opacity(selectedCategory == nil || selectedCategory?.id == item.id ? 1 : 0.4)
                            .accessibilityLabel(item.name).accessibilityValue(store.money(item.amount))
                    }.chartAngleSelection(value: $selectedAngle).chartLegend(.hidden).frame(height: min(donutHeight, 300))
                        .accessibilityIdentifier("categoryChart")
                    if let item = selectedCategory { Text("\(item.name) · \(store.money(item.amount)) / year").font(.subheadline.weight(.semibold)) }
                    ForEach(categories) { item in
                        breakdownAmount(item)
                    }
                }
            }
        }
    }
    private var serviceBreakdown: some View {
        let rows = ranked
        let total = max(rows.reduce(0) { $0 + NSDecimalNumber(decimal: annual($1)).doubleValue }, 1)
        return Surface {
            VStack(spacing: 18) {
                if !rows.isEmpty {
                    Chart(Array(rows.prefix(6))) { record in
                        BarMark(x: .value("Annual cost", NSDecimalNumber(decimal: annual(record)).doubleValue), y: .value("Service", record.id.uuidString))
                            .foregroundStyle(Color.spaceAccent).cornerRadius(4)
                            .accessibilityLabel(record.name).accessibilityValue(store.money(annual(record)))
                            .opacity(serviceSelection == nil || serviceSelection == record.id.uuidString ? 1 : 0.4)
                    }
                    .chartYSelection(value: $serviceSelection)
                    .chartGesture { proxy in
                        SpatialTapGesture().onEnded { proxy.selectYValue(at: $0.location.y) }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let id = value.as(String.self), let record = rows.first(where: { $0.id.uuidString == id }) { Text(record.name).font(.caption).lineLimit(1) }
                            }
                        }
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: typeSize.isAccessibilitySize ? 2 : 4)) { value in AxisValueLabel { if let amount = value.as(Double.self) { Text(amount, format: .number.notation(.compactName)) } } } }
                    .chartXAxisLabel(store.currency)
                    .frame(height: serviceRowHeight * Double(min(rows.count, 6)) + 35)
                    .accessibilityIdentifier("serviceChart")
                    if let record = rows.first(where: { $0.id.uuidString == serviceSelection }) {
                        Text("\(record.name) · \(store.money(annual(record))) / year").font(.subheadline.weight(.semibold))
                    }
                }
                ForEach(rows) { record in
                    Button { selectedService = record } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ViewThatFits(in: .horizontal) {
                                HStack { Text(record.name); Spacer(); Text(store.money(annual(record))).fontWeight(.semibold) }
                                VStack(alignment: .leading, spacing: 4) { Text(record.name); Text(store.money(annual(record))).fontWeight(.semibold) }
                            }.font(.subheadline)
                            ProgressView(value: NSDecimalNumber(decimal: annual(record)).doubleValue, total: total).tint(.spaceAccent)
                        }.foregroundStyle(.primary)
                    }.buttonStyle(.plain)
                }
                if rows.isEmpty { Text("No converted amounts available.").foregroundStyle(.secondary) }
            }
        }
    }
    private var currencyBreakdown: some View {
        Surface {
            VStack(spacing: 18) {
                ForEach(currencies) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        breakdownAmount(item)
                        ProgressView(value: item.value, total: max(currencies.reduce(0) { $0 + $1.value }, 1)).tint(.spaceBlue)
                    }
                }
                if currencies.isEmpty { Text("Exchange rates are needed for this breakdown.").foregroundStyle(.secondary) }
            }
        }
    }
    @ViewBuilder private func breakdownAmount(_ item: BreakdownItem) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).foregroundStyle(.secondary)
                Text(store.money(item.amount)).fontWeight(.semibold)
            }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LabeledContent(item.name, value: store.money(item.amount)).font(.subheadline)
        }
    }
    private func annual(_ record: SubscriptionRecord) -> Decimal { (store.converted(record) ?? 0) * record.interval.periodsPerYear }
}
