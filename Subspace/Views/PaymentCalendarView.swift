import SwiftUI
import SubspaceCore

struct PaymentCalendarView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var cursor = Calendar.current.startOfDay(for: .now)
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var annual = false
    @State private var selected: SubscriptionRecord?
    private var calendar: Calendar { .current }
    private var year: Int { calendar.component(.year, from: cursor) }
    private var dayPayments: [Payment] {
        guard let end = calendar.date(byAdding: .day, value: 1, to: selectedDay) else { return [] }
        return store.payments(in: DateInterval(start: selectedDay, end: end))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Picker("Calendar mode", selection: $annual) { Text("Month").tag(false); Text("Year").tag(true) }.pickerStyle(.segmented)
                    GlassEffectContainer {
                        HStack {
                            Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.glass).accessibilityLabel("Previous period").disabled(year <= 1900)
                            Spacer()
                            Text(annual ? String(year) : cursor.formatted(.dateTime.month(.wide).year())).font(.title3.bold())
                            Spacer()
                            Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.glass).accessibilityLabel("Next period").disabled(year >= 2200)
                        }
                    }
                    RateNotice()
                    if annual {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(1...12, id: \.self) { month in
                                if let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)), let end = calendar.date(byAdding: .month, value: 1, to: date) {
                                    let payments = store.payments(in: DateInterval(start: date, end: end))
                                    Button { cursor = date; selectedDay = date; annual = false } label: {
                                        Surface {
                                            VStack(alignment: .leading, spacing: 12) {
                                                Text(date.formatted(.dateTime.month(.wide))).font(.headline)
                                                Text(store.money(store.total(payments))).font(.subheadline.weight(.semibold)).foregroundStyle(Color.spaceAccent)
                                                Text("\(payments.count) payments").font(.caption).foregroundStyle(.secondary)
                                                HStack(spacing: 3) { ForEach(0..<min(payments.count, 7), id: \.self) { _ in Circle().fill(Color.spaceAccent).frame(width: 5, height: 5) } }
                                            }.frame(minHeight: 100, alignment: .top)
                                        }
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    } else {
                        Surface { monthGrid }
                        SectionTitle(title: selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day()), subtitle: "\(dayPayments.count) scheduled payments · \(store.money(store.total(dayPayments)))")
                        if dayPayments.isEmpty {
                            ContentUnavailableView("A quiet day", systemImage: "calendar.badge.checkmark", description: Text("No subscription payments are scheduled."))
                        } else {
                            Surface {
                                VStack(spacing: 12) { ForEach(dayPayments) { payment in Button { selected = payment.subscription } label: { SubscriptionRow(record: payment.subscription, date: payment.date) }.buttonStyle(.plain) } }
                            }
                        }
                    }
                    Text("Calendar amounts are scheduled estimates, not confirmed bank transactions. Past dates are reconstructed from your current schedules.").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }.background { SpaceBackground() }.navigationTitle("Payment calendar").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(item: $selected) { SubscriptionDetail(record: $0) }
        }
    }
    private var monthGrid: some View {
        let components = calendar.dateComponents([.year, .month], from: cursor)
        let first = calendar.date(from: components) ?? cursor
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 0
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let end = calendar.date(byAdding: .month, value: 1, to: first) ?? first
        let payments = store.payments(in: DateInterval(start: first, end: end))
        let grouped = Dictionary(grouping: payments) { calendar.component(.day, from: $0.date) }
        return VStack(spacing: 14) {
            HStack { ForEach(0..<7, id: \.self) { index in Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7]).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity) } }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 10) {
                ForEach(0..<(offset + count), id: \.self) { index in
                    if index < offset { Color.clear.frame(height: 54) }
                    else {
                        let day = index - offset + 1
                        let date = calendar.date(byAdding: .day, value: day - 1, to: first) ?? first
                        let isSelected = calendar.isDate(date, inSameDayAs: selectedDay)
                        Button { selectedDay = date } label: {
                            VStack(spacing: 6) {
                                Text("\(day)").font(.subheadline.weight(isSelected ? .bold : .regular))
                                Circle().fill((grouped[day]?.isEmpty == false) ? Color.spaceAccent : .clear).frame(width: 5, height: 5)
                            }.frame(maxWidth: .infinity, minHeight: 50).background(isSelected ? Color.spaceAccent.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(grouped[day]?.count ?? 0) payments, \(store.money(store.total(grouped[day] ?? [])))")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
    }
    private func shift(_ direction: Int) {
        if let date = calendar.date(byAdding: annual ? .year : .month, value: direction, to: cursor) { cursor = date }
    }
}
