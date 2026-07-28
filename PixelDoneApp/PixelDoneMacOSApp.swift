import SwiftData
import SwiftUI
import UserNotifications

@main
struct PixelDoneMacOSApp: App {
    private let modelContainer: ModelContainer
    private let notificationDelegate: PixelDoneNotificationDelegate
    @State private var store: PixelDoneStore

    init() {
        let container = PixelDonePersistence.makeContainer()
        let attachmentService = PixelDoneAttachmentService()
        modelContainer = container
        let store = PixelDoneStore(
            repository: PixelDoneRepository(modelContainer: container),
            notificationService: PixelDoneNotificationService(),
            attachmentService: attachmentService,
            cloudCoordinator: CloudCoordinator(
                configuration: AppConfiguration.supabase,
                bundleIdentifier: "com.milesxue.pixeldone.macos",
                attachmentService: attachmentService
            )
        )
        let delegate = PixelDoneNotificationDelegate(store: store)
        notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
        _store = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup("PixelDone", id: "main") {
            PixelDoneRootView(store: store)
                .modelContainer(modelContainer)
                .preferredColorScheme(store.preferredColorScheme)
                .environment(\.locale, store.appLocale)
                .environment(
                    \.layoutDirection,
                    store.appLayoutDirection
                )
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
                .environment(\.locale, store.appLocale)
                .environment(
                    \.layoutDirection,
                    store.appLayoutDirection
                )
        }

        MenuBarExtra("PixelDone", systemImage: "checklist") {
            PixelDoneMenuBarView(store: store)
        }
    }
}
