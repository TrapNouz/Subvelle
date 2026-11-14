import SwiftUI
import SwiftData
import SubspaceCore

#if DEBUG
/// Only XCUITest can opt in. No fixture records or test-store resets ship in Release.
@MainActor enum UITestSupport {
    static func bootstrap() throws -> (ModelContainer, AppStore)? {
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing") else { return nil }
        let environment = ProcessInfo.processInfo.environment
        guard let rawID = environment["SUBSPACE_UI_TEST_ID"], let id = UUID(uuidString: rawID),
              let defaults = UserDefaults(suiteName: "ui-tests." + id.uuidString) else { throw DataError.invalid("Invalid UI-test session.") }
        let folder = URL.applicationSupportDirectory.appendingPathComponent("UITesting", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
        if environment["SUBSPACE_UI_TEST_RESET"] == "1" {
            if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
            defaults.removePersistentDomain(forName: "ui-tests." + id.uuidString)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let cache = environment["SUBSPACE_UI_TEST_RATES"]?.data(using: .utf8) { defaults.set(cache, forKey: "exchangeRates") }
        defaults.set(environment["SUBSPACE_UI_TEST_APPEARANCE"] == "light" ? "system" : "dark", forKey: "appearance")
        let container = try Persistence.container(url: folder.appendingPathComponent("Subscriptions.store"))
        let store = AppStore(container: container, defaults: defaults)
        if let data = environment["SUBSPACE_UI_TEST_BACKUP"]?.data(using: .utf8) { _ = try store.importBackup(data) }
        return (container, store)
    }
}
#endif

private struct UITestingOverrides: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            let environment = ProcessInfo.processInfo.environment
            content
                .dynamicTypeSize(environment["SUBSPACE_UI_TEST_LARGE_TEXT"] == "1" ? .accessibility5 : typeSize)
                .environment(\.accessibilityReduceMotion, environment["SUBSPACE_UI_TEST_REDUCE_MOTION"] == "1" || reduceMotion)
                .environment(\.accessibilityReduceTransparency, environment["SUBSPACE_UI_TEST_REDUCE_TRANSPARENCY"] == "1" || reduceTransparency)
                .preferredColorScheme(environment["SUBSPACE_UI_TEST_APPEARANCE"] == "light" ? .light : .dark)
        } else { content }
        #else
        content
        #endif
    }
}
extension View {
    func uiTestingOverrides() -> some View { modifier(UITestingOverrides()) }
}
