import SwiftUI
import UIKit
import SubspaceCore

extension Color {
    static let spaceBackground = Color(red: 0.025, green: 0.025, blue: 0.045)
    static let spaceAccent = Color(red: 0.64, green: 0.55, blue: 1)
    static let spaceBlue = Color(red: 0.35, green: 0.65, blue: 1)
}
struct SpaceBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack(alignment: .topTrailing) {
            (scheme == .dark ? Color.spaceBackground : Color(uiColor: .systemGroupedBackground))
            Ellipse().fill(Color.spaceAccent.opacity(scheme == .dark ? 0.13 : 0.07)).frame(width: 300, height: 350).blur(radius: 90).offset(x: 110, y: -150)
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}
struct Surface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 26))
            .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(.primary.opacity(0.065), lineWidth: 1) }
    }
}
struct ServiceIcon: View {
    let record: SubscriptionRecord
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15).fill(LinearGradient(colors: [Color.spaceAccent.opacity(0.3), Color.spaceBlue.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: UIImage(systemName: record.symbol) == nil ? "creditcard.fill" : record.symbol).font(.title3.weight(.semibold)).foregroundStyle(Color.spaceAccent)
        }.frame(width: 48, height: 48).accessibilityHidden(true)
    }
}
struct SubscriptionRow: View {
    let record: SubscriptionRecord
    var date: Date? = nil
    var body: some View {
        HStack(spacing: 14) {
            ServiceIcon(record: record)
            VStack(alignment: .leading, spacing: 5) {
                Text(record.name).font(.headline).foregroundStyle(.primary)
                Text(date.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "\(record.category.rawValue) · \(record.interval.label)").font(.caption).foregroundStyle(.secondary)
                if record.status != .active || record.archived { Text(record.archived ? "Archived" : record.status.rawValue.capitalized).font(.caption).foregroundStyle(Color.spaceAccent) }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Money.format(record.amount, currency: record.currency)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).multilineTextAlignment(.trailing)
                Text(record.currency).font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6).contentShape(Rectangle())
    }
}
struct SectionTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct RateNotice: View {
    @Environment(AppStore.self) private var store
    private var missing: [String] { Set(store.records.filter { !$0.archived && $0.status == .active && store.converted($0) == nil }.map(\.currency)).sorted() }
    var body: some View {
        if !missing.isEmpty {
            Label("Partial totals · missing rates for \(missing.joined(separator: ", ")). Refresh rates in Settings.", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange).padding().frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        } else if store.rates.isStale && store.records.contains(where: { $0.currency != store.currency }) {
            Label("Using cached exchange rates. Update in Settings.", systemImage: "clock.arrow.circlepath").font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var adding = false
    var body: some View {
        @Bindable var store = store
        TabView {
            Tab("Overview", systemImage: "square.grid.2x2.fill") { OverviewView() }
            Tab("Subscriptions", systemImage: "rectangle.stack.fill") { SubscriptionsView() }
            Tab("Analytics", systemImage: "chart.xyaxis.line") { AnalyticsView() }
            Tab("Settings", systemImage: "gearshape.fill") { SettingsView() }
        }
        .tint(.spaceAccent)
        .tabBarMinimizeBehavior(.onScrollDown)
        .safeAreaInset(edge: .bottom, alignment: .trailing) {
            GlassEffectContainer {
                Button { adding = true } label: { Label("Add subscription", systemImage: "plus").font(.subheadline.weight(.semibold)).padding(.vertical, 5) }
                    .buttonStyle(.glassProminent).tint(.spaceAccent)
            }.padding(.horizontal, 20).padding(.bottom, 8)
        }
        .sheet(isPresented: $adding) { PresetPicker() }
        .alert("Subspace", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .task {
            if store.rates.isStale { await store.refreshRates() }
            store.scheduleNotifications()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.scheduleNotifications() }
        }
    }
}
