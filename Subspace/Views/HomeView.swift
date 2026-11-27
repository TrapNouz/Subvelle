import SwiftUI
import SubspaceCore

/// The single home screen: a header and four folders. Each folder shows a live preview and opens
/// into a panel that pops out of it over a blurred home screen (see `RootView`).
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Where each folder tile sits on screen, so its panel can grow out of it.
    @Binding var tileFrames: [AppTab: CGRect]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                RateNotice()
                BackupNotice()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 300 : 150), spacing: 16)], spacing: 16) {
                    ForEach(AppTab.allCases) { tab in
                        FolderTile(tab: tab)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { tileFrames[tab] = $0 }
                    }
                }
                if let next = store.upcoming.first {
                    Button { navigation.show(.overview) } label: {
                        Surface {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Next payment").font(.subheadline).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(countdown(next.date)).font(.caption.weight(.semibold)).foregroundStyle(Color.spaceAccent)
                                }
                                SubscriptionRow(record: next.subscription, date: next.date)
                            }
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("homeNextPayment")
                }
                PrivacyFootnote().accessibilityIdentifier("homeBottom")
            }
            .padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("homeScroll")
        .background { SpaceBackground() }
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Subvelle").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button { navigation.sheet = .add } label: {
                Image(systemName: "plus").font(.title3.weight(.semibold)).frame(width: 30, height: 30)
            }
            .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
            .accessibilityLabel("Add subscription").accessibilityIdentifier("addSubscription")
        }
    }
    private func countdown(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: date).day ?? 0
        return days == 0 ? "Today" : days == 1 ? "Tomorrow" : "In \(days) days"
    }
}

/// A rounded "folder" with a preview of what is inside, like a home-screen folder.
struct FolderTile: View {
    let tab: AppTab
    @Environment(AppStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Button { navigation.show(tab) } label: {
            VStack(alignment: .leading, spacing: 12) {
                preview.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                HStack(spacing: 6) {
                    Image(systemName: tab.symbol).font(.footnote.weight(.semibold)).foregroundStyle(Color.spaceAccent)
                    Text(tab.title).font(.headline).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? 200 : 168, alignment: .leading)
            .aspectRatio(typeSize.isAccessibilitySize ? nil : 1, contentMode: .fit)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .buttonStyle(FolderPressStyle())
        .accessibilityLabel("\(tab.title), \(summary)")
        .accessibilityHint("Opens \(tab.title)")
        .accessibilityIdentifier("folder-\(tab.rawValue)")
    }
    private var summary: String {
        switch tab {
        case .overview: "\(store.money(store.summary.monthly)) per month"
        case .subscriptions: "\(store.visible.count) subscriptions"
        case .analytics: "Charts and payment calendar"
        case .settings: store.backupFolderName == nil ? "Currency, reminders and backups" : "Automatic backup on"
        }
    }
    @ViewBuilder private var preview: some View {
        switch tab {
        case .overview:
            VStack(alignment: .leading, spacing: 4) {
                Text("Monthly").font(.caption).foregroundStyle(.secondary)
                Text(store.money(store.summary.monthly)).font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).accessibilityIdentifier("homeMonthlyAverage")
                Text("\(store.summary.activeCount) active").font(.caption).foregroundStyle(.secondary)
            }
        case .subscriptions:
            let shown = Array(store.visible.prefix(9))
            if shown.isEmpty {
                Image(systemName: "plus.rectangle.on.rectangle").font(.title).foregroundStyle(Color.spaceAccent.opacity(0.8))
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), alignment: .leading, spacing: 6) {
                    ForEach(shown) { record in ServiceIcon(record: record, size: 30) }
                }
            }
        case .analytics:
            MiniYearChart()
        case .settings:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "gearshape.2.fill").font(.title).foregroundStyle(Color.spaceAccent.opacity(0.85))
                Label(store.backupFolderName == nil ? "Backup off" : "Backup on", systemImage: store.backupFolderName == nil ? "icloud.slash" : "checkmark.icloud")
                    .font(.caption).foregroundStyle(.secondary)
                Text(store.currency).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Twelve small bars: scheduled payments in each month of the current year.
private struct MiniYearChart: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: .now)
        let month = calendar.component(.month, from: .now)
        let totals: [Double] = (1...12).map { m in
            guard let start = calendar.date(from: DateComponents(year: year, month: m, day: 1)),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return 0 }
            return NSDecimalNumber(decimal: store.total(store.payments(in: DateInterval(start: start, end: end)))).doubleValue
        }
        let top = max(totals.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(totals.enumerated()), id: \.offset) { index, value in
                Capsule().fill(index + 1 < month ? Color.spaceBlue : Color.spaceAccent)
                    .frame(maxWidth: .infinity).frame(height: max(4, 58 * value / top))
            }
        }
        .frame(height: 58, alignment: .bottom).padding(.top, 8)
    }
}

/// Folders shrink slightly while pressed, like home-screen icons.
private struct FolderPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// An open folder: the section's full screen in a rounded panel, closed with ✕, a tap outside,
/// a swipe down on the handle, or the accessibility escape gesture.
struct FolderPanel: View {
    let tab: AppTab
    @Environment(AppNavigation.self) private var navigation
    @State private var dragOffset: CGFloat = 0
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 34, style: .continuous)
        VStack(spacing: 0) {
            Capsule().fill(Color.secondary.opacity(0.5)).frame(width: 40, height: 5)
                .frame(maxWidth: .infinity).frame(height: 16)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { dragOffset = max(0, $0.translation.height) }
                        .onEnded { value in
                            if value.translation.height > 120 || value.predictedEndTranslation.height > 260 { navigation.closeFolder() }
                            else { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { dragOffset = 0 } }
                        }
                )
                .accessibilityHidden(true)
            content
        }
        .background { SpaceBackground() }
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.08), lineWidth: 1) }
        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
        // Real margins: the blurred home screen frames the open folder and can be tapped to close it.
        .padding(.horizontal, 14).padding(.top, 24).padding(.bottom, 14)
        .offset(y: dragOffset)
        .scaleEffect(1 - min(dragOffset, 300) / 3000)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("folderPanel")
        .accessibilityAction(.escape) { navigation.closeFolder() }
    }
    @ViewBuilder private var content: some View {
        switch tab {
        case .overview: OverviewView()
        case .subscriptions: SubscriptionsView()
        case .analytics: AnalyticsView()
        case .settings: SettingsView()
        }
    }
}
