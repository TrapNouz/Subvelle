import SwiftUI
import UIKit
import Observation
import SubspaceCore

extension Color {
    static let spaceBackground = Color(red: 0.045, green: 0.045, blue: 0.055)
    static let spaceAction = Color(red: 0.42, green: 0.28, blue: 0.82)
    static let spaceAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.69, green: 0.60, blue: 1, alpha: 1)
            : UIColor(red: 0.36, green: 0.23, blue: 0.72, alpha: 1)
    })
    static let spaceBlue = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.35, green: 0.65, blue: 1, alpha: 1)
            : UIColor(red: 0.14, green: 0.37, blue: 0.70, alpha: 1)
    })
}
struct SpaceBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        (scheme == .dark ? Color.spaceBackground : Color(uiColor: .systemGroupedBackground))
            .ignoresSafeArea().accessibilityHidden(true)
    }
}
struct Surface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}
struct ServiceIcon: View {
    let record: SubscriptionRecord
    private var initials: String { String(record.name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased() }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13).fill(Color.spaceAccent.opacity(0.14))
            VStack(spacing: 2) {
                Image(systemName: UIImage(systemName: record.symbol) == nil ? "creditcard.fill" : record.symbol)
                    .font(.system(size: 17, weight: .medium))
                if !initials.isEmpty { Text(initials).font(.system(size: 9, weight: .bold)) }
            }
        }.foregroundStyle(Color.spaceAccent).frame(width: 44, height: 44).accessibilityHidden(true)
    }
}
struct SubscriptionRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let record: SubscriptionRecord
    var date: Date? = nil
    private var renewal: Date? { date ?? RecurrenceEngine().nextPayment(record)?.date }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ServiceIcon(record: record)
            VStack(alignment: .leading, spacing: 5) {
                if typeSize.isAccessibilitySize {
                    title
                    price
                } else {
                    HStack(alignment: .firstTextBaseline) { title; Spacer(minLength: 8); price }
                }
                Text(record.interval.label + " · " + record.currency).font(.caption).foregroundStyle(.secondary)
                if let renewal { Text("Renews \(renewal.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
                if record.status != .active || record.archived {
                    Text(record.archived ? "Archived" : record.status.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(.vertical, 7).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
    private var title: some View { Text(record.name).font(.headline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true) }
    private var price: some View { Text(Money.format(record.amount, currency: record.currency)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true) }
}
struct SectionTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct RateNotice: View {
    @Environment(AppStore.self) private var store
    private var missing: [String] { Set(store.records.filter { !$0.archived && $0.status == .active && store.converted($0) == nil }.map(\.currency)).sorted() }
    var body: some View {
        if !missing.isEmpty {
            Label("Partial totals · missing rates for \(missing.joined(separator: ", ")). Refresh in Settings.", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange).padding().frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        } else if store.rates.isStale && store.records.contains(where: { $0.currency != store.currency }) {
            Label("Using cached rates · update in Settings", systemImage: "clock.arrow.circlepath").font(.caption).foregroundStyle(.secondary)
        }
    }
}

enum AppTab: String, CaseIterable { case overview, subscriptions, analytics, settings }
enum AppSheet: String, Identifiable { case add; var id: String { rawValue } }
@MainActor @Observable final class AppNavigation {
    var selected: AppTab = .overview
    var sheet: AppSheet?
}
private struct SubscriptionToolbar: ViewModifier {
    @Environment(AppNavigation.self) private var navigation
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add subscription", systemImage: "plus") { navigation.sheet = .add }
                    .labelStyle(.iconOnly).accessibilityIdentifier("addSubscription")
            }
        }
    }
}
extension View {
    func subscriptionToolbar() -> some View { modifier(SubscriptionToolbar()) }
}
struct AddSubscriptionButton: View {
    @Environment(AppNavigation.self) private var navigation
    var body: some View {
        Button("Add subscription", systemImage: "plus") { navigation.sheet = .add }
            .buttonStyle(.glassProminent).tint(.spaceAction).controlSize(.large)
            .accessibilityIdentifier("emptyStateAdd")
    }
}
struct SubscriptionEmptyState: View {
    let title: String
    let message: String
    let symbol: String
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: symbol).font(.largeTitle).foregroundStyle(Color.spaceAccent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text(message).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                AddSubscriptionButton()
            }.padding(.vertical, 4)
        }.accessibilityIdentifier("subscriptionEmptyState")
    }
}
struct PrivacyFootnote: View {
    var body: some View {
        Label("Private by design. Stored on your iPhone.", systemImage: "lock.shield")
            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigation = AppNavigation()
    var body: some View {
        @Bindable var store = store
        @Bindable var navigation = navigation
        // A nonoptional selection always refers to one of four visible tabs (iOS 27).
        TabView(selection: $navigation.selected) {
            Tab("Overview", systemImage: "square.grid.2x2", value: AppTab.overview) { OverviewView() }
            Tab("Subscriptions", systemImage: "rectangle.stack", value: AppTab.subscriptions) { SubscriptionsView() }
            Tab("Analytics", systemImage: "chart.xyaxis.line", value: AppTab.analytics) { AnalyticsView() }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) { SettingsView() }
        }
        .tint(.spaceAccent).tabBarMinimizeBehavior(.never)
        // No bottom overlay/inset: TabView alone owns its navigation safe area.
        .sheet(item: $navigation.sheet) { _ in PresetPicker() }
        .environment(navigation)
        .sensoryFeedback(.selection, trigger: navigation.selected)
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        .alert("Subspace", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-testing") { return }
            #endif
            if store.rates.isStale { await store.refreshRates(silent: true) }
            store.scheduleNotifications()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.scheduleNotifications() }
        }
    }
}
