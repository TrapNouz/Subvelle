import SwiftUI
import SwiftData
import SubspaceCore

@main struct SubspaceApp: App {
    private let container: ModelContainer?
    private let launchError: String?
    @State private var store: AppStore?
    init() {
        do {
            let (container, store) = try AppBootstrap.make()
            self.container = container; launchError = nil
            _store = State(initialValue: store)
        } catch { container = nil; launchError = error.localizedDescription }
    }
    var body: some Scene {
        WindowGroup {
            if let store, let container {
                RootView().environment(store).modelContainer(container)
                    .preferredColorScheme(store.appearance == "dark" ? .dark : nil)
                    .uiTestingOverrides()
            } else {
                ContentUnavailableView("Storage unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text("Subvelle could not open its local database. Your data has not been deleted. Restart the app or restore a device backup.\n\n\(launchError ?? "Unknown storage error")"))
                    .preferredColorScheme(.dark)
            }
        }
    }
}

@MainActor enum AppBootstrap {
    static func make() throws -> (ModelContainer, AppStore) {
        #if DEBUG
        if let result = try UITestSupport.bootstrap() { return result }
        #endif
        let container = try Persistence.container()
        return (container, AppStore(container: container))
    }
}
