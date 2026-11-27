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
extension Color {
    /// A colour from "RRGGBB".
    init(hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
struct ServiceIcon: View {
    let record: SubscriptionRecord
    var size: CGFloat = 44
    var body: some View { BrandIcon(name: record.name, symbol: record.symbol, size: size) }
}
/// App-icon-style tile for a service: its logo on its brand colour when known (Simple Icons, CC0),
/// a monogram on the brand colour when the brand has no available logo, otherwise the chosen symbol.
struct BrandIcon: View {
    let name: String
    var symbol: String = "creditcard.fill"
    var size: CGFloat = 44
    private var initials: String { String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased() }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
        Group {
            if let brand = BrandCatalog.brand(for: name) {
                let foreground: Color = brand.prefersDarkForeground ? .black : .white
                ZStack {
                    shape.fill(Color(hex: brand.hex))
                    if let logo = brand.logo {
                        Image(logo).renderingMode(.template).resizable().scaledToFit()
                            .foregroundStyle(foreground).padding(size * 0.22)
                    } else {
                        Text(initials).font(.system(size: size * (initials.count > 1 ? 0.34 : 0.44), weight: .bold, design: .rounded))
                            .foregroundStyle(foreground).minimumScaleFactor(0.5).lineLimit(1).padding(.horizontal, size * 0.08)
                    }
                }
                // Near-black brand tiles get a hairline so they stay visible on the dark background.
                .overlay { shape.strokeBorder(.white.opacity(brand.luminance < 0.03 ? 0.16 : 0), lineWidth: 1) }
            } else {
                ZStack {
                    shape.fill(Color.spaceAccent.opacity(0.14))
                    VStack(spacing: 2) {
                        Image(systemName: UIImage(systemName: symbol) == nil ? "creditcard.fill" : symbol)
                            .font(.system(size: size * 0.38, weight: .medium))
                        if !initials.isEmpty && size >= 36 { Text(initials).font(.system(size: size * 0.2, weight: .bold)) }
                    }.foregroundStyle(Color.spaceAccent)
                }
            }
        }
        .frame(width: size, height: size).accessibilityHidden(true)
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

/// Nudges toward Settings when no backup has completed for a week, or the automatic backup is failing.
struct BackupNotice: View {
    @Environment(AppStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    var body: some View {
        if !store.records.isEmpty, store.backupProblem != nil || BackupPlan.isOverdue(lastBackup: store.lastBackup) {
            Button { navigation.show(.settings) } label: {
                Label(store.backupProblem != nil ? "Automatic backup failed · review it in Settings" : "No backup in the last \(BackupPlan.overdueAfterDays) days · set up iCloud Drive backup in Settings", systemImage: "exclamationmark.icloud")
                    .font(.caption).foregroundStyle(.orange).padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(.plain).accessibilityIdentifier("backupNotice")
        }
    }
}

/// The four sections, shown as folders on the home screen.
enum AppTab: String, CaseIterable, Identifiable {
    case overview, subscriptions, analytics, settings
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .subscriptions: "rectangle.stack.fill"
        case .analytics: "chart.xyaxis.line"
        case .settings: "gearshape.fill"
        }
    }
}
enum AppSheet: String, Identifiable { case add; var id: String { rawValue } }
@MainActor @Observable final class AppNavigation {
    /// The open folder; nil shows the home screen.
    var openFolder: AppTab?
    var sheet: AppSheet?
    /// Set by the root view from Reduce Motion: a cross-fade instead of the pop-out spring.
    var reduceMotion = false
    var folderAnimation: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.46, dampingFraction: 0.84) }
    func show(_ tab: AppTab) { withAnimation(folderAnimation) { openFolder = tab } }
    func closeFolder() { withAnimation(folderAnimation) { openFolder = nil } }
}
private struct SubscriptionToolbar: ViewModifier {
    @Environment(AppNavigation.self) private var navigation
    func body(content: Content) -> some View {
        content.toolbar {
            if navigation.openFolder != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { navigation.closeFolder() }
                        .labelStyle(.iconOnly).accessibilityIdentifier("closeFolder")
                }
            }
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
    /// A backup handed to the app by Files or the share sheet, waiting for confirmation.
    @State private var openedBackup: OpenedBackup?
    @State private var tileFrames: [AppTab: CGRect] = [:]
    @State private var rootFrame: CGRect = .zero
    var body: some View {
        @Bindable var store = store
        @Bindable var navigation = navigation
        ZStack {
            HomeView(tileFrames: $tileFrames)
                .scaleEffect(navigation.openFolder == nil || reduceMotion ? 1 : 0.94)
                .allowsHitTesting(navigation.openFolder == nil)
                .accessibilityHidden(navigation.openFolder != nil)
            if let tab = navigation.openFolder {
                // The home screen stays visible behind the open folder, blurred by a system material
                // (which becomes opaque with Reduce Transparency). Tapping it closes the folder.
                Rectangle().fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.12))
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { navigation.closeFolder() }
                    .accessibilityHidden(true)
                    .transition(.opacity)
                    .zIndex(1)
                FolderPanel(tab: tab)
                    .id(tab)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.22, anchor: anchor(for: tab)).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rootFrame = $0 }
        .tint(.spaceAccent)
        .sheet(item: $navigation.sheet) { _ in PresetPicker() }
        .environment(navigation)
        .sensoryFeedback(.selection, trigger: navigation.openFolder)
        .onAppear { navigation.reduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, value in navigation.reduceMotion = value }
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        .alert("Subvelle", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-testing") { return }
            #endif
            if store.rates.isStale { await store.refreshRates(silent: true) }
            store.scheduleNotifications()
            await store.backUpIfDue()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshDerived(); store.scheduleNotifications(); Task { await store.backUpIfDue() } }
        }
        // "Share → Subvelle" or "Open in Subvelle" from Files, Mail, Messages and other apps.
        .onOpenURL { url in
            guard url.isFileURL else { return }
            Task {
                do {
                    let (data, count) = try await Task.detached(priority: .userInitiated) { try AppStore.readBackupFile(at: url) }.value
                    navigation.sheet = nil
                    openedBackup = OpenedBackup(data: data, count: count)
                } catch { store.error = error.localizedDescription }
            }
        }
        // On its own view so it never competes with the error alert above.
        .background {
            Color.clear.alert("Import \(openedBackup?.count ?? 0) subscriptions?", isPresented: Binding(get: { openedBackup != nil }, set: { if !$0 { openedBackup = nil } })) {
                Button("Merge backup") {
                    guard let backup = openedBackup else { return }
                    openedBackup = nil
                    do { _ = try store.importBackup(backup.data); navigation.show(.subscriptions) }
                    catch { store.error = error.localizedDescription }
                }
                Button("Cancel", role: .cancel) { openedBackup = nil }
            } message: { Text("From a Subvelle backup file. Matching subscriptions will be replaced and others kept.") }
        }
    }
}

extension RootView {
    /// The open folder grows out of its tile: the scale anchor is the tile's centre on screen.
    fileprivate func anchor(for tab: AppTab) -> UnitPoint {
        guard let tile = tileFrames[tab], rootFrame.width > 0, rootFrame.height > 0 else { return .center }
        return UnitPoint(x: (tile.midX - rootFrame.minX) / rootFrame.width, y: (tile.midY - rootFrame.minY) / rootFrame.height)
    }
}

struct OpenedBackup: Equatable {
    let data: Data
    let count: Int
}
