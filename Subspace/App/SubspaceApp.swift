import SwiftUI
import SwiftData

@main struct SubspaceApp: App {
    private let container: ModelContainer?
    private let launchError: String?
    @State private var store: AppStore?
    init() {
        do {
            let container = try Persistence.container()
            self.container = container; launchError = nil
            _store = State(initialValue: AppStore(container: container))
        } catch { container = nil; launchError = error.localizedDescription }
    }
    var body: some Scene {
        WindowGroup {
            if let store, let container {
                RootView().environment(store).modelContainer(container)
                    .preferredColorScheme(store.appearance == "dark" ? .dark : nil)
            } else {
                ContentUnavailableView("Storage unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text("Subspace could not open its local database. Your data has not been deleted. Restart the app or restore a device backup.\n\n\(launchError ?? "Unknown storage error")"))
                    .preferredColorScheme(.dark)
            }
        }
    }
}
