import SwiftUI

@main
struct PixelDoneMacOSApp: App {
    var body: some Scene {
        WindowGroup("PixelDone", id: "main") {
            FoundationHandoffView()
                .frame(minWidth: 1000, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 780)

        Settings {
            FoundationSettingsView()
        }

        MenuBarExtra("PixelDone", systemImage: "checklist") {
            FoundationMenuBarView()
        }
    }
}
