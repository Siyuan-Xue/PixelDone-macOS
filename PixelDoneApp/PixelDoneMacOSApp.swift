import SwiftData
import SwiftUI

@main
struct PixelDoneMacOSApp: App {
    private let modelContainer: ModelContainer
    @State private var store: PixelDoneStore

    init() {
        let container = PixelDonePersistence.makeContainer()
        modelContainer = container
        _store = State(
            initialValue: PixelDoneStore(
                repository: PixelDoneRepository(modelContainer: container)
            )
        )
    }

    var body: some Scene {
        WindowGroup("PixelDone", id: "main") {
            PixelDoneRootView(store: store)
                .modelContainer(modelContainer)
                .preferredColorScheme(store.preferredColorScheme)
                .frame(minWidth: 1000, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            PixelDoneCommands(store: store)
        }

        Settings {
            PixelDoneSettingsView(store: store)
                .modelContainer(modelContainer)
                .preferredColorScheme(store.preferredColorScheme)
        }

        MenuBarExtra("PixelDone", systemImage: "checklist") {
            PixelDoneMenuBarView(store: store)
        }
    }
}
