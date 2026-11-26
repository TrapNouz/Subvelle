import SwiftUI
import SubspaceCore

struct OverviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: SubscriptionRecord?
    private var largest: [SubscriptionRecord] {
        store.visible.filter { $0.status == .active && ($0.endDate.map { $0 >= Calendar.current.startOfDay(for: .now) } ?? true) && store.converted($0) != nil }
            .sorted { normalized($0) > normalized($1) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if store.visible.isEmpty {
                        SubscriptionEmptyState(title: "Make room for clarity", message: "Know what you pay, what’s coming next, and what you could save. Start with one subscription.", symbol: "circle.hexagongrid")
                        Surface {
                            VStack(alignment: .leading, spacing: 18) {
                                benefit("Every payment, together", description: "Track weekly, monthly, annual, and custom plans.", symbol: "rectangle.stack")
                                benefit("A little less surprise", description: "See renewals ahead of time with local reminders.", symbol: "calendar.badge.clock")
                                benefit("The full picture", description: "Understand your average costs in one currency.", symbol: "chart.bar.xaxis")
                            }
                        }
                    } else {
                        monthlyCard
                        RateNotice()
                        BackupNotice()
                        if let next = store.upcoming.first {
                            Surface {
                                Button { selected = next.subscription } label: {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack { Text("Next payment").font(.subheadline).foregroundStyle(.secondary); Spacer(); Text(countdown(next.date)).font(.caption.weight(.semibold)).foregroundStyle(Color.spaceAccent) }
                                        SubscriptionRow(record: next.subscription, date: next.date)
                                    }
                                }.buttonStyle(.plain).accessibilityIdentifier("nextPayment")
                            }
                        }
                        Surface {
                            VStack(alignment: .leading, spacing: 16) {
                                SectionTitle(title: "Your year in payments", subtitle: "Scheduled charges · \(Date.now.formatted(.dateTime.year()))")
                                SpendingChart(compact: true)
                            }
                        }
                        if !store.upcoming.isEmpty {
                            SectionTitle(title: "Upcoming renewals", subtitle: "The next payment for each service")
                            Surface {
                                VStack(spacing: 12) {
                                    ForEach(Array(store.upcoming.prefix(5))) { payment in
                                        Button { selected = payment.subscription } label: { SubscriptionRow(record: payment.subscription, date: payment.date) }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        if !largest.isEmpty {
                            SectionTitle(title: "Largest expenses", subtitle: "Normalized annual cost · \(store.currency)")
                            Surface {
                                VStack(spacing: 16) {
                                    ForEach(Array(largest.prefix(3))) { record in
                                        Button { selected = record } label: {
                                            VStack(alignment: .leading, spacing: 8) {
                                                SubscriptionRow(record: record)
                                                Text("\(store.money(normalized(record))) / year").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                            }
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    PrivacyFootnote().accessibilityIdentifier("overviewBottom")
                }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: store.visible.isEmpty)
            }
            .accessibilityIdentifier("overviewScroll")
            .scrollEdgeEffectStyle(.hard, for: .bottom)
            .background { SpaceBackground() }.navigationTitle("Overview")
            .subscriptionToolbar()
            .sheet(item: $selected) { SubscriptionDetail(record: $0) }
        }
    }
    private var monthlyCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 18) {
                Text("Monthly average").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Text(store.money(store.summary.monthly)).font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText()).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("monthlyAverage")
                Text("Your recurring commitment, averaged over the year.").font(.caption).foregroundStyle(.secondary)
                Divider()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 130), alignment: .leading)], alignment: .leading, spacing: 16) {
                    metric("Annual average", value: store.money(store.summary.annual))
                    metric("Weekly equivalent", value: store.money(store.summary.weekly))
                    metric("Active plans", value: String(store.summary.activeCount))
                }
            }.animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.05), value: store.summary.monthly)
        }
    }
    private func normalized(_ record: SubscriptionRecord) -> Decimal { (store.converted(record) ?? 0) * record.interval.periodsPerYear }
    private func countdown(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: date).day ?? 0
        return days == 0 ? "Today" : days == 1 ? "Tomorrow" : "In \(days) days"
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.headline).monospacedDigit().contentTransition(reduceMotion ? .identity : .numericText()) }
    }
    private func benefit(_ title: String, description: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).foregroundStyle(Color.spaceAccent).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.subheadline.weight(.semibold)); Text(description).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
