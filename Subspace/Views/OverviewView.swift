import SwiftUI
import SubspaceCore

struct OverviewView: View {
    @Environment(AppStore.self) private var store
    @State private var selected: SubscriptionRecord?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased()).font(.caption.weight(.medium)).tracking(1.5).foregroundStyle(.secondary)
                            Text("Your money.\nIn perspective.").font(.largeTitle.bold()).tracking(-1)
                        }
                        Spacer()
                        Image(systemName: "circle.hexagongrid.fill").font(.largeTitle).foregroundStyle(Color.spaceAccent).padding(14).glassEffect(.regular, in: .circle).accessibilityHidden(true)
                    }
                    if store.visible.isEmpty {
                        Surface {
                            ContentUnavailableView("A little clarity starts here", systemImage: "sparkles", description: Text("Add your first subscription to see what’s recurring, what’s next, and what it all adds up to."))
                        }
                    } else {
                        Surface {
                            VStack(alignment: .leading, spacing: 20) {
                                Label("MONTHLY AVERAGE", systemImage: "waveform.path").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                                Text(store.money(store.summary.monthly)).font(.system(.largeTitle, design: .rounded, weight: .bold)).minimumScaleFactor(0.5).contentTransition(.numericText()).foregroundStyle(LinearGradient(colors: [.primary, .spaceAccent], startPoint: .leading, endPoint: .trailing))
                                Text("Normalized across your active subscriptions").font(.caption).foregroundStyle(.secondary)
                                Divider()
                                HStack(alignment: .top) {
                                    metric("Annual", value: store.money(store.summary.annual))
                                    Spacer()
                                    metric("Weekly", value: store.money(store.summary.weekly))
                                    Spacer()
                                    metric("Active", value: "\(store.summary.activeCount)")
                                }
                            }
                        }
                        RateNotice()
                        if let next = store.upcoming.first {
                            Button { selected = next.subscription } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("NEXT PAYMENT").font(.caption.weight(.semibold)).tracking(1)
                                        Text(next.subscription.name).font(.title3.bold())
                                        Text("\(countdown(next.date)) · \(Money.format(next.subscription.amount, currency: next.subscription.currency))").font(.subheadline)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.title3)
                                }.padding(22).foregroundStyle(.primary)
                            }.buttonStyle(.plain).glassEffect(.regular.tint(.spaceAccent.opacity(0.12)).interactive(), in: .rect(cornerRadius: 26))
                        }
                        SectionTitle(title: "The bigger picture", subtitle: "Scheduled payments · \(Date.now.formatted(.dateTime.year()))")
                        Surface { SpendingChart(compact: true) }
                        if !store.upcoming.isEmpty {
                            SectionTitle(title: "Coming up", subtitle: "Your next renewal for each active service")
                            Surface {
                                VStack(spacing: 14) {
                                    ForEach(Array(store.upcoming.prefix(5))) { payment in
                                        Button { selected = payment.subscription } label: { SubscriptionRow(record: payment.subscription, date: payment.date) }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        let largest = store.visible.filter { $0.status == .active && ($0.endDate.map { $0 >= Calendar.current.startOfDay(for: .now) } ?? true) && store.converted($0) != nil }.sorted { normalized($0) > normalized($1) }
                        if !largest.isEmpty {
                            SectionTitle(title: "Largest commitments", subtitle: "Ranked by normalized annual cost in \(store.currency)")
                            Surface {
                                VStack(spacing: 14) {
                                    ForEach(Array(largest.prefix(3))) { record in
                                        Button { selected = record } label: {
                                            HStack {
                                                ServiceIcon(record: record)
                                                Text(record.name).font(.subheadline.weight(.medium))
                                                Spacer()
                                                Text(store.money(normalized(record))).font(.subheadline.weight(.semibold))
                                            }.foregroundStyle(.primary)
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    Text("PRIVATE BY DESIGN · STORED ON YOUR IPHONE").font(.caption2.weight(.medium)).tracking(1).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
                }.padding(20)
            }
            .background { SpaceBackground() }.navigationTitle("Subspace").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selected) { SubscriptionDetail(record: $0) }
            .animation(reduceMotion ? nil : .spring(response: 0.45), value: store.summary.monthly)
        }
    }
    private func normalized(_ record: SubscriptionRecord) -> Decimal { (store.converted(record) ?? 0) * record.interval.periodsPerYear }
    private func countdown(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: date).day ?? 0
        return days == 0 ? "Today" : days == 1 ? "Tomorrow" : "In \(days) days"
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.weight(.semibold)).contentTransition(.numericText()) }.minimumScaleFactor(0.6)
    }
}
